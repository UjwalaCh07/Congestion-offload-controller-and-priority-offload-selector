# Experimental NoC offloading RTL

These modules are standalone experiments. They are not instantiated by, or
connected to, the existing router. No original router, FIFO, arbiter, routing,
package, testbench, or build file is modified.

## Existing router facts and integration boundary

The existing five-port router uses LOCAL, NORTH, SOUTH, EAST, and WEST. Its
default 48-bit flit stores the destination port in bits `[47:45]`; the other
bits are opaque payload. It routes single-flit packets through per-input FIFOs
and transfers a flit using ready/valid handshakes. It has no priority metadata,
congestion indicator, advertised downstream capacity, packet identity, or
packet-level ownership handshake.

Consequently there is no safe adapter here. A future integration must supply
the missing interfaces and use the existing routing policy to certify an
alternate route. The controller does not calculate a route, reserve a receiver
buffer, or implement the existing router's FIFO pop/hold behavior.

## `congestion_offload_controller`

The controller's explicit inputs include a congestion level, a candidate
packet and identity, eligibility, route legality, downstream capacity, and
receiver accept/reject/cancel responses. Its sequence is:

1. Assert congestion after `CONGESTION_PERSIST_CYCLES` consecutive samples
   at or above `ASSERT_THRESHOLD`.
2. Clear congestion after `RECOVERY_PERSIST_CYCLES` consecutive samples at or
   below `RECOVERY_THRESHOLD`. `ASSERT_THRESHOLD` must be greater than
   `RECOVERY_THRESHOLD`; the space between them is the hysteresis band.
3. When congestion is active and all candidate/route/capacity gates pass,
   snapshot the packet and candidate identity and assert the transfer request.
4. Hold request-valid and the snapshotted packet until a terminal event.
   Candidate input changes, including `candidate_valid` dropping, do not
   cancel or retarget a pending request.
5. A sampled receiver acceptance produces a one-cycle `sender_commit` in the
   next state. Rejection or cancellation produces `transfer_failed` and no
   commit. Rejection/cancellation wins if asserted with acceptance.
   Acceptance wins over timeout if simultaneous with the timeout boundary.

The timeout is measured in **full cycles with request-valid asserted**. At
launch edge L, the controller changes from `ST_IDLE` to `ST_WAIT`; request-valid
becomes high after L. The first unanswered request interval is L through the
next rising edge, where the pre-edge timeout count is zero. For timeout N, the
counter is compared with N-1 at each rising edge that samples a pending request:

- N=1: the first unanswered request edge is terminal; request-valid was high
  for the full launch-to-first-response interval.
- N=4: the first three unanswered request edges increment counts 0->1, 1->2,
  and 2->3. The fourth unanswered request edge sees count 3 and enters
  `ST_FAIL`.
- Acceptance sampled on that fourth edge enters `ST_COMMIT` instead, because
  acceptance is tested before timeout.

For any terminal input sampled at edge T, the controller enters the response
state at T's nonblocking-assignment update. `sender_commit` or
`transfer_failed` is high during the following cycle T-to-T+1, with
request-valid low. At T+1 the controller schedules a return to idle. A new
offer can only be launched at a later rising edge that samples idle and
`offload_available`; it cannot overlap the registered response cycle.

### Retry identity contract

Retry state tracks only one candidate identity at a time; it does not maintain
independent simultaneous budgets for several IDs. Failed attempts consume the
budget for the captured identity. A different `candidate_id` may start with a
fresh budget even if `candidate_valid` remains asserted. A source should keep
the same ID for retries of the same packet and use a different ID for a
different packet. A successful transfer sets the tracked identity's budget to
`MAX_OFFLOAD_ATTEMPTS`, so leaving that same ID valid does not immediately
transfer it again. A source may deassert `candidate_valid` while the controller
is idle to clear the remembered budget before reusing an ID.

An ID change during a pending request does not change the outstanding
transaction: the original packet stays offered until terminal response. When
that transaction ends, the new ID can be treated as the next candidate. If an
ID is reused without an idle `candidate_valid` deassertion, it is considered
the same identity and shares its retry budget.

The controller only generates control outputs; it cannot guarantee that an
external source physically retains ownership until commit or removes its
packet after commit. The integration must obey that ownership contract.
Receiver acceptance must mean the receiver has reserved storage and accepted
responsibility for the complete packet, not merely acknowledged an offer.

## `priority_offload_selector`

The selector only considers candidates when congestion is at or above the
provided threshold and the candidate is valid, route-legal, and capacity
eligible. Numeric encoding is selected by `HIGHER_VALUE_IS_HIGHER_PRIORITY`:

- `0` (default): smaller numbers mean more urgent. A value at or above
  `lowest_offload_priority` is eligible; among unaged eligible candidates,
  the largest numeric value is selected first.
- `1`: larger numbers mean more urgent. A value at or below the cutoff is
  eligible; among unaged eligible candidates, the smallest numeric value is
  selected first.

Equal selection priority is resolved by a rotating tie-break. After one
candidate's successful transfer, pulse only its bit in `candidate_serviced`;
the next search starts at the following candidate and wraps around. If more
than one service bit is asserted in a cycle, the entire service vector is
ignored: no age is reset and the round-robin pointer does not move.
`candidate_serviced` must represent one completed transfer, not a selection
or an offer.

### Aging behavior

An eligible candidate accumulates age each clock while it remains valid,
route-legal, capacity-eligible, and congestion-qualified. Its age saturates at
`AGE_LIMIT_CYCLES`. An aged candidate **overrides the priority cutoff** and is
considered before all unaged eligible candidates. Among aged candidates, the
largest age wins, with the round-robin distance breaking ties. Among unaged
candidates, normal priority ranking applies, then round-robin distance.

Age resets on reset, candidate invalidity, illegal route, insufficient
capacity, congestion below threshold, or a valid single-candidate service
pulse. A multi-bit service vector is rejected as a whole and does not reset
any age. The selector is combinational and does not buffer or lock a packet;
the integration must hold the selected identity and packet stable across a
separate transfer protocol.

## Parameters and validation

- `PACKET_WIDTH`, `CANDIDATE_ID_WIDTH`, `LEVEL_WIDTH`,
  `PRIORITY_WIDTH`, `NUM_CANDIDATES`, and `INDEX_WIDTH` must be positive
  (the selector's `INDEX_WIDTH` must represent every candidate index).
- Congestion thresholds must be non-negative, fit in `LEVEL_WIDTH`, and
  `ASSERT_THRESHOLD` must exceed `RECOVERY_THRESHOLD`.
- Congestion/recovery persistence, timeout, retry limit, and aging limit must
  each be at least one.
- `ATTEMPT_COUNT_WIDTH` must represent values through
  `MAX_OFFLOAD_ATTEMPTS`.
- Non-positive storage widths are guarded for elaboration, then rejected by
  the modules' parameter checks.

## Simulation

Run in the RTL project directory using Icarus Verilog:

```powershell
iverilog -g2012 -Wall -s tb_offloading -o experimental_offloading\offloading_test experimental_offloading\congestion_offload_controller.sv experimental_offloading\priority_offload_selector.sv experimental_offloading\tb_offloading.sv
vvp experimental_offloading\offloading_test
```

The self-checking testbench covers congestion persistence/recovery/hysteresis,
candidate gates, payload stability, accept/reject/cancel/timeout precedence,
identity-based retries, reset while pending, both priority encodings,
round-robin ties and wrap, the stale-distance regression, age promotion,
saturation and invalidation (capacity loss, congestion loss, route-legality
loss, and candidate invalidation, each with a full re-aging interval),
simultaneous service indications, one-hot and candidate-gate assertions,
request/payload stability and registered terminal-event monitors, successful
identity exhaustion, one candidate, and minimum legal parameter values.

The testbench uses a small protocol reference state machine (`IDLE`, `WAIT`,
`EXPECT_COMMIT`, `EXPECT_FAILURE`) with its own timeout counter. At each rising
edge it first compares the pre-update DUT outputs against the reference
state, then samples terminal inputs and updates the reference state using
N-1 timeout counting and reject/cancel/accept precedence. The model does not
read the DUT's internal state or timeout counter. Launch is observed through
the public `offload_available` interface, while request persistence, payload
stability, response type, and response cycle are checked independently.
Stimulus changes occur after a rising edge through the `step` task or in a
settled combinational interval, not in the monitor's sampling region.

The timeout=1 boundary instance checks request launch followed by exactly one
unanswered request interval and failure. The timeout=4 instance checks each
pre-boundary request interval, failure after exactly four unanswered cycles,
and acceptance on the fourth-cycle boundary. Direct checks also test reject
and cancel precedence, and the reference monitor rejects early, late, missing,
or repeated response pulses. These are procedural simulation checks; no
concurrent SVA coverage is claimed.

Mutation checks were also performed by temporarily changing only the approved
controller source and then restoring it: a timeout threshold one cycle early
was rejected by the pre-boundary request check; a threshold one cycle late was
rejected by the exactly-four-cycles timeout check; an early combinational
commit was rejected by the monitor before its registered response cycle; and
a delayed commit was rejected by the directed acceptance response-cycle
check. The final passing regression was rerun after restoring the intended
controller.

Selector interface checks run after each falling edge, when combinational
outputs have settled. They verify one-hot-or-zero output, selected-index
range, matching one-hot bit, congestion qualification, and candidate
valid/route/capacity gates. The multi-service case is an intentional contract
test: the vector is ignored as a whole and neither the service pointer nor
service-reset behavior is applied. The stale-distance regression makes
candidate zero a provisional eligible winner, lets candidate one replace it
by priority, then checks that candidate two's equal priority does not displace
candidate one's better round-robin distance in either encoding.

Latest local Icarus regression: **PASS, 101 self-checks, no `-Wall`
compiler warnings**. The test verifies only standalone RTL behavior, not
router integration, routing correctness, deadlock freedom, or production
readiness.

Simulation is not a proof of deadlock freedom, route safety, or correctness of
a future adapter. The original router does not provide an alternate route or
packet-level reservation semantics. An integrator must ensure that every
candidate route is legal under the existing routing restrictions, reserve
complete-packet downstream capacity before acceptance, preserve packet
identity/loop metadata, and prove resource-dependency/liveness properties for
the combined system. A hop/attempt limit alone does not prove deadlock
freedom. These blocks are experimental and not production-ready.

## Standalone SNN congestion predictor

[`snn_congestion_predictor.sv`](./snn_congestion_predictor.sv) is an isolated
per-direction feature predictor. It is **not connected** to the router or
offloading controller. The router does not expose occupancy, trends,
windowed-traffic counts, or congestion-history signals; a future adapter must
derive and supply them without changing the existing router in this task.

Default `NUM_DIRECTIONS=5` can represent LOCAL/NORTH/SOUTH/EAST/WEST outputs.
Each direction has a separate three-neuron integer LIF network:

```text
occupancy trend + traffic count -> fast LIF ----\
                                                 -> readout LIF -> prediction
occupancy threshold + recent history -> pressure LIF --/
```

Inputs are sampled only on that direction's `feature_valid` rising edge.
`traffic_count` is a count already accumulated by an external adapter over one
fixed, documented observation window; this RTL does not count traffic itself.
If `feature_valid` is low, neuron state, prediction, and activity hold; the
corresponding `prediction_valid` bit is low on the next sampled clock.
`prediction_valid` mirrors the sampled per-direction update pulse for one
cycle when the source provides a one-cycle pulse. The prediction and score
hold between updates.

Trend encoding is `2'b00` falling, `2'b01` stable, `2'b10` rising. Occupancy
and traffic are unsigned quantized inputs. The fast neuron receives
`FAST_TREND_WEIGHT` for rising trend and `FAST_TRAFFIC_WEIGHT` when traffic
meets `TRAFFIC_THRESHOLD`. The pressure neuron receives
`PRESSURE_OCCUPANCY_WEIGHT` when occupancy meets `OCCUPANCY_THRESHOLD`, and
`PRESSURE_HISTORY_WEIGHT` when `recent_congestion` is set. History is expected
to represent a past observation, not future data.

For each of the fast, pressure, and readout neurons, one valid observation
performs:

```text
leaked = max(previous_membrane - LEAK_PER_OBSERVATION, 0)
integrated = min(leaked + weighted_spike_inputs, 2^MEMBRANE_WIDTH - 1)
spike = integrated >= neuron_threshold
next_membrane = spike ? integrated - neuron_threshold : integrated
```

The readout consumes the fast/pressure spikes computed from the current
observation. `predicted_congestion` updates to the readout spike on that
observation; it is an early-warning/risk indication based on current and
remembered features, **not a calibrated probability**. The module has no
intrinsic physical prediction horizon. The comparison experiment below
evaluates it against a two-observation-window future event. `prediction_activity`
is the saturated readout's integrated pre-reset potential, useful as a small
integer score. Weights and thresholds are integer parameters. The default
weights are provisional and **untrained**; no training dataset or learned
weights were supplied. No multipliers or floating-point datapath are used.

All directions instantiate separate scalar neuron state. Membrane potential
and arithmetic are bounded. Parameter checks require positive direction and
feature widths, `MEMBRANE_WIDTH>=2`, `TREND_WIDTH>=2`, in-range feature
thresholds, positive spike thresholds, and non-negative weights/leak that fit
the membrane representation. The minimum tested configuration uses one-bit
occupancy and traffic features and a two-bit membrane.

## SNN verification and baseline experiment

Run the directed SNN checks:

```powershell
iverilog -g2012 -Wall -s tb_snn_congestion_predictor -o experimental_offloading\snn_test experimental_offloading\snn_congestion_predictor.sv experimental_offloading\tb_snn_congestion_predictor.sv
vvp experimental_offloading\snn_test
```

The separately selected negative-parameter top should compile cleanly and
terminate at simulation time zero with the documented range-check fatal:

```powershell
iverilog -g2012 -Wall -s tb_snn_invalid_parameter -o experimental_offloading\invalid_parameter_test experimental_offloading\snn_congestion_predictor.sv experimental_offloading\tb_snn_congestion_predictor.sv
vvp experimental_offloading\invalid_parameter_test
```

Run the SNN/baseline evaluation:

```powershell
iverilog -g2012 -Wall -s tb_snn_baseline_comparison -o experimental_offloading\snn_compare experimental_offloading\snn_congestion_predictor.sv experimental_offloading\tb_snn_baseline_comparison.sv
vvp experimental_offloading\snn_compare
```

The directed testbench checks deterministic reset, low/stable inputs,
increasing occupancy with rising traffic, sustained high occupancy/history,
falling occupancy/traffic, valid-window-only updates, repeated observations,
readout leak to and hold at zero, isolated fast- and pressure-neuron
contributions, exact output-threshold firing, simultaneous hidden spikes,
repeated saturation, reset during active prediction, independent directions,
held prediction between updates, and minimum legal parameter widths. Its
invalid-parameter top is run separately and is expected to terminate with the
predictor's occupancy-threshold range fatal. These are procedural simulation
checks, not formal proof.

The comparison applies the same ten deterministic synthetic traces to the
SNN and a simple combinational baseline. The 18-window traces cover gradual
ramps independently on both directions, two-window and single-window bursts,
sustained congestion, recovery, two-direction events at different times,
stable occupancy with high traffic, rising occupancy with low traffic, and
repeated bursts. Every trace is evaluated independently per direction; a
crossing or prediction from one direction is never reused for the other. The
baseline predicts when `occupancy>=10`, or
`(occupancy>=6 && trend==rising)`, or
`(traffic_count>=6 && trend==rising)`.

Ground truth is occupancy at least 12 in either of the next two observation
windows. Only current-window features and past-history are supplied to either
predictor; future values are used only to label the sample. The final two
windows are excluded from each trace, giving 16 scored windows per trace and
320 direction-window classifications total.

Timing values are measured separately for every scenario/direction pair:

- **First assertion index** is the first positive prediction from trace index
  zero within the scored 0–15 window range; its average includes only pairs
  where that predictor asserted.
- **Detection delay** is the first positive prediction at or after that
  pair's first occupancy-threshold crossing within the scored range, minus
  the crossing index. Crossings in the unscored tail are not detection-eligible.
  A scored crossing with no later positive prediction has no measured delay.
- **Early lead** is the earliest positive prediction strictly before the
  crossing, but only when that sample's two-window future-event label is
  positive; lead is crossing index minus prediction index.
- Per-direction and global averages use real-valued division and print both
  measured-pair counts and detection-eligible crossing-pair counts. Empty metric sets print
  `N/A` with a zero count. Pair output uses index `-1` when no crossing or
  prediction is present.

Confusion accounting checks that TP+FN equals the positive-label count,
FP+TN equals the negative-label count, and each predictor accounts for every
scored direction-window exactly once. Precision, recall, and false-positive
rate print `N/A` when their denominator is zero. The comparison harness
checks lookahead bounds and verifies early predictions precede that
direction's own crossing. These are simulation checks, not formal proof.

Latest measured Icarus results, from 160 observation samples / 320
direction-window classifications:

| Predictor | TP | FP | TN | FN | Precision | Recall |
|---|---:|---:|---:|---:|---:|---:|
| SNN (provisional weights) | 41 | 13 | 233 | 33 | 75.93% | 55.41% |
| Threshold/trend baseline | 60 | 24 | 222 | 14 | 71.43% | 81.08% |

Across both directions, early lead was SNN 6/3 = 2.00 windows over 9 eligible
scenario/direction pairs and baseline 6/3 = 2.00 windows over the same 9
pairs. Post-crossing detection delay was SNN 3/7 = 0.43 windows across 10
detection-eligible crossings and baseline 0/10 = 0.00 windows. First
assertion index averaged 4.88 over 8 asserted SNN scenario/direction pairs
and 3.91 over 11 baseline pairs.
Direction-specific totals are emitted by simulation. In this synthetic
evaluation the SNN had slightly higher measured precision but lower recall
than the baseline. These small synthetic results are not evidence of
real-traffic predictive accuracy, power, timing, area, or research novelty.

## Verification tools and integration next step

The latest local Icarus runs passed: offloading **101 checks**, directed SNN
**56 checks**, legacy SNN/baseline methodology **255 checks**, generated-trace
SNN comparison **9364 checks**, and the updated parameter sweep **20921 checks**.
All were compiled with `-g2012 -Wall`; the final compile runs reported no
warnings. The invalid-parameter probe is expected to terminate with a fatal
parameter diagnostic. Git, Verilator, Yosys, and Quartus executables were not
available in the environment, so no Git diff, lint, synthesis, resource,
timing, or EP4CE10 utilization results are claimed.

## Reproducible SNN parameter sweep

[`tb_snn_parameter_sweep.sv`](./tb_snn_parameter_sweep.sv) instantiates
21 legal configurations: the unchanged default parameter set plus two
one-factor variants for each of fast and pressure neuron thresholds, output
threshold, fast trend/traffic weights, pressure occupancy/history weights,
output fast/pressure weights, and leak. The swept values are explicit in the
configuration functions at the start of the testbench. This is a small
one-factor-at-a-time screening sweep; it does not explore parameter
interactions and does not train weights.

Run it with:

```powershell
iverilog -g2012 -Wall -s tb_snn_parameter_sweep -o experimental_offloading\sweep_test experimental_offloading\snn_traffic_traces.sv experimental_offloading\snn_congestion_predictor.sv experimental_offloading\tb_snn_parameter_sweep.sv
vvp experimental_offloading\sweep_test
```

The sweep uses the shared deterministic trace generator described below.
Complete trace families 0–5 (trace IDs 0–23, 1440 scored direction-windows)
are tuning-only. Families 6–7 (trace IDs 24–31, 480 scored direction-windows)
are held out. The family-based split keeps the four variants of any family
together, so near-identical variants cannot straddle the split. The held-out
families are intentionally different from tuning families and therefore
represent a small synthetic distribution shift. Every configuration is
scored on tuning traces; only the tuning-selected configuration is evaluated
on held-out traces. Selection never reads held-out labels or metrics.

The selection objective is maximum tuning micro-F1, computed as
`2*TP/(2*TP+FP+FN)`. Ties are broken by fewer false positives, then more true
positives, then lower configuration index. The testbench prints every tuning
configuration's parameter values, confusion counts, precision, recall,
false-positive rate, and eligible early-warning/detection-delay counts and
averages, followed by the selected configuration's held-out metrics.
Early-warning pairs are reported as observed warnings / crossings eligible
for a pre-crossing horizon label; detection pairs are reported as detected
crossings / crossings within the scored window range. Timing averages are
over observed warnings or detections, respectively.

Latest measured sweep: config 5 won tuning micro-F1 (0.627986). It retains
the default predictor values except `OUTPUT_THRESHOLD=4` (the default is 6).
This is experimental only and was not copied into the predictor RTL.

| Set | TP | FP | TN | FN | Precision | Recall | FPR | Early lead | Detection delay |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Tuning, config 5 (1440 windows) | 184 | 163 | 1038 | 55 | 53.03% | 76.99% | 13.57% | 4/16 warnings/eligible = 2.00 windows | 21/21 detections/eligible = 0.05 windows |
| Held-out, config 5 (480 windows) | 80 | 18 | 352 | 30 | 81.63% | 72.73% | 4.86% | N/A; 0 warnings / 14 eligible | 14/14 detections/eligible = 0.14 windows |

Config 19 was the winner on the earlier, much smaller trace set. Under the
expanded family-separated set it is not selected. Config 19's comparison
results are reported separately below. These outcomes are sensitive to the
synthetic trace design and small held-out sample; they are not estimates of
real workload generalization. No tuned parameter is applied to default RTL.

### Deterministic generated-trace evaluation

[`snn_traffic_traces.sv`](./snn_traffic_traces.sv) is the shared deterministic
generator. It uses no `$random` state: trace ID, direction, and sample index
fully determine occupancy and traffic count. Four variants per family vary
onset, duration, level, direction, or traffic-count profile. The eight
families are gradual ramps, short bursts, sustained congestion, recovery,
repeated bursts, stable high traffic, directional asymmetry, and staggered
onset. The tuning partition contains the first six complete families; the
last two complete families are held out. Keeping families intact avoids a
variant of one generated pattern being used for tuning while another
near-identical variant is held out.

Run the three-way evaluation:

```powershell
iverilog -g2012 -Wall -s tb_snn_generalization -o experimental_offloading\generalization_test experimental_offloading\snn_traffic_traces.sv experimental_offloading\snn_congestion_predictor.sv experimental_offloading\tb_snn_generalization.sv
vvp experimental_offloading\generalization_test
```

The rule-based baseline, default predictor, and experimental config 19
(`LEAK_PER_OBSERVATION=0`) receive identical current-window features. All
three use the same 32-sample traces, 30 scored windows, occupancy event
threshold 12, and ground truth of occupancy at least 12 in either of the next
two windows. No future value is supplied as a predictor feature. The
testbench checks all lookaheads are in bounds, repeats generator queries to
check deterministic reproduction, verifies the family split, and checks
classification accounting across all methods and partitions. It prints
per-trace confusion counts, per-family confusion counts, partition aggregates,
precision, recall, false-positive rate, and eligible early-warning and
detection-delay statistics.

Timing denominators count crossings, not samples: early warning is eligible
for a crossing after trace index zero where a pre-crossing scored sample can
have a positive horizon label; detection delay is eligible only when the
first crossing lies in the scored range. A metric with no measured cases is
reported as `N/A`, while the eligible count is retained. Precision is
TP/(TP+FP), recall is TP/(TP+FN), and false-positive rate is FP/(FP+TN).

Measured results (all metrics use identical labels and windows):

| Partition | Method | Direction-windows | TP | FP | TN | FN | Precision | Recall | FPR | Early warnings / eligible; mean lead | Detections / eligible; mean delay |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Tuning | Rule baseline | 1440 | 185 | 83 | 1118 | 54 | 69.03% | 77.41% | 6.91% | 4/16; 2.00 | 21/21; 0.00 |
| Tuning | Default SNN | 1440 | 123 | 90 | 1111 | 116 | 57.75% | 51.46% | 7.49% | 4/16; 2.00 | 17/21; 1.59 |
| Tuning | Config 19 | 1440 | 164 | 165 | 1036 | 75 | 49.85% | 68.62% | 13.74% | 4/16; 1.50 | 21/21; 0.81 |
| Held out | Rule baseline | 480 | 82 | 14 | 356 | 28 | 85.42% | 74.55% | 3.78% | N/A (0/14) | 14/14; 0.00 |
| Held out | Default SNN | 480 | 46 | 8 | 362 | 64 | 85.19% | 41.82% | 2.16% | N/A (0/14) | 14/14; 1.14 |
| Held out | Config 19 | 480 | 68 | 26 | 344 | 42 | 72.34% | 61.82% | 7.03% | N/A (0/14) | 14/14; 1.00 |

Per-family TP/FP/TN/FN values are emitted by the simulation. Each family
contains four traces, 240 scored direction-windows; consequently family
results expose that aggregate metrics mix substantially different cases.
For example, the stable-high-traffic family has no future threshold crossing
labels in these traces but does produce false positives. The held-out set has
only two families/eight traces and is not evidence of generalization to
realistic NoC workloads.

### Synthesis portability and cost risks

The predictor uses synchronous state with asynchronous active-low reset,
constant-width integer arithmetic, bounded per-neuron membrane registers, and
no behavioral delays, dynamic memory, or real-valued datapath. Its
`MEMBRANE_WIDTH+2` accumulator can represent the prior membrane plus two
maximum-width weights before saturation. State and combinational arithmetic
scale approximately linearly with `NUM_DIRECTIONS`; membrane width affects
register and adder/comparator widths. These are structural observations, not
measured hardware cost.

The parameter checks use time-zero `$fatal` statements, which are useful in
simulation but may need synthesis-tool-specific exclusion or elaboration-time
parameter validation. The packed multidimensional ports and sized casts also
need confirmation in the selected synthesis-tool version. Yosys and Quartus
were not installed here, so no synthesis result or resource/timing claim is
made. Suggested future probes, from the project RTL directory, are:

```powershell
yosys -p "read_verilog -sv experimental_offloading/snn_congestion_predictor.sv; hierarchy -check -top snn_congestion_predictor; proc; opt; check; synth -top snn_congestion_predictor; stat"
quartus_sh --flow compile snn_predictor_synthesis
```

The Quartus command requires a separately prepared
`snn_predictor_synthesis.qpf/.qsf` that selects the target device, sets
`snn_congestion_predictor` as top-level entity, and includes the predictor
source. No such project was created by this task.

Next, build and verify a separate adapter that exports measured per-output
occupancy, trend, windowed traffic count, and past congestion history. It may
use the predictor only as an advisory feature. Any eventual offload policy
must still obtain route legality from the established routing restrictions,
check/reserve destination capacity, preserve packet ownership through
acceptance, and be analyzed for channel dependencies and liveness. Do not
connect predictions directly to router outputs or treat a prediction as
permission to route.
