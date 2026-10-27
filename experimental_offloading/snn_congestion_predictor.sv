`timescale 1ns/1ps

module snn_congestion_predictor #(
    parameter int NUM_DIRECTIONS = 5,
    parameter int OCCUPANCY_WIDTH = 4,
    parameter int TRAFFIC_COUNT_WIDTH = 4,
    parameter int MEMBRANE_WIDTH = 8,
    parameter int OCCUPANCY_THRESHOLD = 8,
    parameter int TRAFFIC_THRESHOLD = 4,
    parameter int FAST_NEURON_THRESHOLD = 4,
    parameter int PRESSURE_NEURON_THRESHOLD = 4,
    parameter int OUTPUT_NEURON_THRESHOLD = 6,
    parameter int FAST_TREND_WEIGHT = 2,
    parameter int FAST_TRAFFIC_WEIGHT = 2,
    parameter int PRESSURE_OCCUPANCY_WEIGHT = 2,
    parameter int PRESSURE_HISTORY_WEIGHT = 2,
    parameter int OUTPUT_FAST_WEIGHT = 4,
    parameter int OUTPUT_PRESSURE_WEIGHT = 4,
    parameter int LEAK_PER_OBSERVATION = 1,
    parameter int TREND_WIDTH = 2
) (
    input  logic clk,
    input  logic rst_n,
    input  logic [((NUM_DIRECTIONS > 0) ? NUM_DIRECTIONS : 1)-1:0]
        feature_valid,
    input  logic [((NUM_DIRECTIONS > 0) ? NUM_DIRECTIONS : 1)-1:0]
        [((OCCUPANCY_WIDTH > 0) ? OCCUPANCY_WIDTH : 1)-1:0]
        occupancy,
    input  logic [((NUM_DIRECTIONS > 0) ? NUM_DIRECTIONS : 1)-1:0]
        [((TREND_WIDTH > 0) ? TREND_WIDTH : 1)-1:0]
        occupancy_trend,
    input  logic [((NUM_DIRECTIONS > 0) ? NUM_DIRECTIONS : 1)-1:0]
        [((TRAFFIC_COUNT_WIDTH > 0) ? TRAFFIC_COUNT_WIDTH : 1)-1:0]
        traffic_count,
    input  logic [((NUM_DIRECTIONS > 0) ? NUM_DIRECTIONS : 1)-1:0]
        recent_congestion,
    output logic [((NUM_DIRECTIONS > 0) ? NUM_DIRECTIONS : 1)-1:0]
        prediction_valid,
    output logic [((NUM_DIRECTIONS > 0) ? NUM_DIRECTIONS : 1)-1:0]
        predicted_congestion,
    output logic [((NUM_DIRECTIONS > 0) ? NUM_DIRECTIONS : 1)-1:0]
        [((MEMBRANE_WIDTH > 0) ? MEMBRANE_WIDTH : 1)-1:0]
        prediction_activity
);

    localparam int SAFE_DIRECTIONS = (NUM_DIRECTIONS > 0) ? NUM_DIRECTIONS : 1;
    localparam int SAFE_OCCUPANCY_WIDTH =
        (OCCUPANCY_WIDTH > 0) ? OCCUPANCY_WIDTH : 1;
    localparam int SAFE_TRAFFIC_WIDTH =
        (TRAFFIC_COUNT_WIDTH > 0) ? TRAFFIC_COUNT_WIDTH : 1;
    localparam int SAFE_MEMBRANE_WIDTH =
        (MEMBRANE_WIDTH > 0) ? MEMBRANE_WIDTH : 1;
    localparam int SAFE_TREND_WIDTH = (TREND_WIDTH > 0) ? TREND_WIDTH : 1;
    localparam int REQUIRED_TREND_WIDTH = 2;

    for (genvar direction = 0; direction < SAFE_DIRECTIONS; direction++) begin : g_direction
        snn_lif_direction #(
            .OCCUPANCY_WIDTH(SAFE_OCCUPANCY_WIDTH),
            .TRAFFIC_COUNT_WIDTH(SAFE_TRAFFIC_WIDTH),
            .TREND_WIDTH(SAFE_TREND_WIDTH),
            .MEMBRANE_WIDTH(SAFE_MEMBRANE_WIDTH),
            .OCCUPANCY_THRESHOLD(OCCUPANCY_THRESHOLD),
            .TRAFFIC_THRESHOLD(TRAFFIC_THRESHOLD),
            .FAST_NEURON_THRESHOLD(FAST_NEURON_THRESHOLD),
            .PRESSURE_NEURON_THRESHOLD(PRESSURE_NEURON_THRESHOLD),
            .OUTPUT_NEURON_THRESHOLD(OUTPUT_NEURON_THRESHOLD),
            .FAST_TREND_WEIGHT(FAST_TREND_WEIGHT),
            .FAST_TRAFFIC_WEIGHT(FAST_TRAFFIC_WEIGHT),
            .PRESSURE_OCCUPANCY_WEIGHT(PRESSURE_OCCUPANCY_WEIGHT),
            .PRESSURE_HISTORY_WEIGHT(PRESSURE_HISTORY_WEIGHT),
            .OUTPUT_FAST_WEIGHT(OUTPUT_FAST_WEIGHT),
            .OUTPUT_PRESSURE_WEIGHT(OUTPUT_PRESSURE_WEIGHT),
            .LEAK_PER_OBSERVATION(LEAK_PER_OBSERVATION)
        ) lif (
            .clk,
            .rst_n,
            .feature_valid(feature_valid[direction]),
            .occupancy(occupancy[direction]),
            .occupancy_trend(occupancy_trend[direction]),
            .traffic_count(traffic_count[direction]),
            .recent_congestion(recent_congestion[direction]),
            .prediction_valid(prediction_valid[direction]),
            .predicted_congestion(predicted_congestion[direction]),
            .prediction_activity(prediction_activity[direction])
        );
    end

    initial begin
        if (NUM_DIRECTIONS < 1)
            $fatal(1, "NUM_DIRECTIONS must be at least one");
        if (OCCUPANCY_WIDTH < 1 || TRAFFIC_COUNT_WIDTH < 1
            || MEMBRANE_WIDTH < 2 || TREND_WIDTH < REQUIRED_TREND_WIDTH)
            $fatal(1, "Feature widths must be positive and membrane/trend widths at least two");
        if (OCCUPANCY_THRESHOLD < 0 || TRAFFIC_THRESHOLD < 0
            || FAST_NEURON_THRESHOLD < 1 || PRESSURE_NEURON_THRESHOLD < 1
            || OUTPUT_NEURON_THRESHOLD < 1 || LEAK_PER_OBSERVATION < 0
            || FAST_TREND_WEIGHT < 0 || FAST_TRAFFIC_WEIGHT < 0
            || PRESSURE_OCCUPANCY_WEIGHT < 0 || PRESSURE_HISTORY_WEIGHT < 0
            || OUTPUT_FAST_WEIGHT < 0 || OUTPUT_PRESSURE_WEIGHT < 0)
            $fatal(1, "Thresholds, weights, and leak must be non-negative; spike thresholds must be positive");
        if (OCCUPANCY_WIDTH < 32
            && 64'(OCCUPANCY_THRESHOLD) >= (64'd1 << OCCUPANCY_WIDTH))
            $fatal(1, "OCCUPANCY_THRESHOLD does not fit OCCUPANCY_WIDTH");
        if (TRAFFIC_COUNT_WIDTH < 32
            && 64'(TRAFFIC_THRESHOLD) >= (64'd1 << TRAFFIC_COUNT_WIDTH))
            $fatal(1, "TRAFFIC_THRESHOLD does not fit TRAFFIC_COUNT_WIDTH");
        if (MEMBRANE_WIDTH < 32
            && ((64'(FAST_NEURON_THRESHOLD) >= (64'd1 << MEMBRANE_WIDTH))
                || (64'(PRESSURE_NEURON_THRESHOLD) >= (64'd1 << MEMBRANE_WIDTH))
                || (64'(OUTPUT_NEURON_THRESHOLD) >= (64'd1 << MEMBRANE_WIDTH))
                || (64'(LEAK_PER_OBSERVATION) >= (64'd1 << MEMBRANE_WIDTH))
                || (64'(FAST_TREND_WEIGHT) >= (64'd1 << MEMBRANE_WIDTH))
                || (64'(FAST_TRAFFIC_WEIGHT) >= (64'd1 << MEMBRANE_WIDTH))
                || (64'(PRESSURE_OCCUPANCY_WEIGHT) >= (64'd1 << MEMBRANE_WIDTH))
                || (64'(PRESSURE_HISTORY_WEIGHT) >= (64'd1 << MEMBRANE_WIDTH))
                || (64'(OUTPUT_FAST_WEIGHT) >= (64'd1 << MEMBRANE_WIDTH))
                || (64'(OUTPUT_PRESSURE_WEIGHT) >= (64'd1 << MEMBRANE_WIDTH))))
            $fatal(1, "LIF thresholds, weights, and leak must fit MEMBRANE_WIDTH");
    end
endmodule

module snn_lif_direction #(
    parameter int OCCUPANCY_WIDTH = 4,
    parameter int TRAFFIC_COUNT_WIDTH = 4,
    parameter int TREND_WIDTH = 2,
    parameter int MEMBRANE_WIDTH = 8,
    parameter int OCCUPANCY_THRESHOLD = 8,
    parameter int TRAFFIC_THRESHOLD = 4,
    parameter int FAST_NEURON_THRESHOLD = 4,
    parameter int PRESSURE_NEURON_THRESHOLD = 4,
    parameter int OUTPUT_NEURON_THRESHOLD = 6,
    parameter int FAST_TREND_WEIGHT = 2,
    parameter int FAST_TRAFFIC_WEIGHT = 2,
    parameter int PRESSURE_OCCUPANCY_WEIGHT = 2,
    parameter int PRESSURE_HISTORY_WEIGHT = 2,
    parameter int OUTPUT_FAST_WEIGHT = 4,
    parameter int OUTPUT_PRESSURE_WEIGHT = 4,
    parameter int LEAK_PER_OBSERVATION = 1
) (
    input  logic clk,
    input  logic rst_n,
    input  logic feature_valid,
    input  logic [OCCUPANCY_WIDTH-1:0] occupancy,
    input  logic [TREND_WIDTH-1:0] occupancy_trend,
    input  logic [TRAFFIC_COUNT_WIDTH-1:0] traffic_count,
    input  logic recent_congestion,
    output logic prediction_valid,
    output logic predicted_congestion,
    output logic [MEMBRANE_WIDTH-1:0] prediction_activity
);

    localparam int ACCUMULATOR_WIDTH = MEMBRANE_WIDTH + 2;
    localparam logic [TREND_WIDTH-1:0] TREND_RISING = 2'd2;
    localparam logic [OCCUPANCY_WIDTH-1:0] OCCUPANCY_THRESHOLD_VALUE =
        OCCUPANCY_THRESHOLD;
    localparam logic [TRAFFIC_COUNT_WIDTH-1:0] TRAFFIC_THRESHOLD_VALUE =
        TRAFFIC_THRESHOLD;
    localparam logic [MEMBRANE_WIDTH-1:0] FAST_THRESHOLD_VALUE =
        FAST_NEURON_THRESHOLD;
    localparam logic [MEMBRANE_WIDTH-1:0] PRESSURE_THRESHOLD_VALUE =
        PRESSURE_NEURON_THRESHOLD;
    localparam logic [MEMBRANE_WIDTH-1:0] OUTPUT_THRESHOLD_VALUE =
        OUTPUT_NEURON_THRESHOLD;
    localparam logic [MEMBRANE_WIDTH-1:0] LEAK_VALUE =
        LEAK_PER_OBSERVATION;
    localparam logic [MEMBRANE_WIDTH-1:0] MAX_POTENTIAL = '1;
    localparam logic [ACCUMULATOR_WIDTH-1:0] MAX_POTENTIAL_EXTENDED =
        MAX_POTENTIAL;
    localparam logic [ACCUMULATOR_WIDTH-1:0] FAST_TREND_WEIGHT_VALUE =
        FAST_TREND_WEIGHT;
    localparam logic [ACCUMULATOR_WIDTH-1:0] FAST_TRAFFIC_WEIGHT_VALUE =
        FAST_TRAFFIC_WEIGHT;
    localparam logic [ACCUMULATOR_WIDTH-1:0] PRESSURE_OCCUPANCY_WEIGHT_VALUE =
        PRESSURE_OCCUPANCY_WEIGHT;
    localparam logic [ACCUMULATOR_WIDTH-1:0] PRESSURE_HISTORY_WEIGHT_VALUE =
        PRESSURE_HISTORY_WEIGHT;
    localparam logic [ACCUMULATOR_WIDTH-1:0] OUTPUT_FAST_WEIGHT_VALUE =
        OUTPUT_FAST_WEIGHT;
    localparam logic [ACCUMULATOR_WIDTH-1:0] OUTPUT_PRESSURE_WEIGHT_VALUE =
        OUTPUT_PRESSURE_WEIGHT;

    logic [MEMBRANE_WIDTH-1:0] fast_membrane;
    logic [MEMBRANE_WIDTH-1:0] pressure_membrane;
    logic [MEMBRANE_WIDTH-1:0] output_membrane;
    logic [MEMBRANE_WIDTH-1:0] fast_membrane_next;
    logic [MEMBRANE_WIDTH-1:0] pressure_membrane_next;
    logic [MEMBRANE_WIDTH-1:0] output_membrane_next;
    logic [MEMBRANE_WIDTH-1:0] output_activity_next;
    logic output_spike_next;

    always @* begin : p_lif
        logic [MEMBRANE_WIDTH-1:0] fast_leaked;
        logic [MEMBRANE_WIDTH-1:0] pressure_leaked;
        logic [MEMBRANE_WIDTH-1:0] output_leaked;
        logic [ACCUMULATOR_WIDTH-1:0] fast_sum;
        logic [ACCUMULATOR_WIDTH-1:0] pressure_sum;
        logic [ACCUMULATOR_WIDTH-1:0] output_sum;
        logic [MEMBRANE_WIDTH-1:0] fast_integrated;
        logic [MEMBRANE_WIDTH-1:0] pressure_integrated;
        logic [MEMBRANE_WIDTH-1:0] output_integrated;
        logic fast_spike;
        logic pressure_spike;

        fast_leaked = (fast_membrane > LEAK_VALUE)
            ? fast_membrane - LEAK_VALUE : '0;
        pressure_leaked = (pressure_membrane > LEAK_VALUE)
            ? pressure_membrane - LEAK_VALUE : '0;
        output_leaked = (output_membrane > LEAK_VALUE)
            ? output_membrane - LEAK_VALUE : '0;

        fast_sum = {{(ACCUMULATOR_WIDTH-MEMBRANE_WIDTH){1'b0}}, fast_leaked};
        if (occupancy_trend == TREND_RISING)
            fast_sum = fast_sum + FAST_TREND_WEIGHT_VALUE;
        if (traffic_count >= TRAFFIC_THRESHOLD_VALUE)
            fast_sum = fast_sum + FAST_TRAFFIC_WEIGHT_VALUE;
        fast_integrated = (fast_sum > MAX_POTENTIAL_EXTENDED)
            ? MAX_POTENTIAL : fast_sum[MEMBRANE_WIDTH-1:0];
        fast_spike = (fast_integrated >= FAST_THRESHOLD_VALUE);
        fast_membrane_next = fast_spike
            ? fast_integrated - FAST_THRESHOLD_VALUE : fast_integrated;

        pressure_sum =
            {{(ACCUMULATOR_WIDTH-MEMBRANE_WIDTH){1'b0}}, pressure_leaked};
        if (occupancy >= OCCUPANCY_THRESHOLD_VALUE)
            pressure_sum = pressure_sum + PRESSURE_OCCUPANCY_WEIGHT_VALUE;
        if (recent_congestion)
            pressure_sum = pressure_sum + PRESSURE_HISTORY_WEIGHT_VALUE;
        pressure_integrated = (pressure_sum > MAX_POTENTIAL_EXTENDED)
            ? MAX_POTENTIAL : pressure_sum[MEMBRANE_WIDTH-1:0];
        pressure_spike = (pressure_integrated >= PRESSURE_THRESHOLD_VALUE);
        pressure_membrane_next = pressure_spike
            ? pressure_integrated - PRESSURE_THRESHOLD_VALUE : pressure_integrated;

        output_sum =
            {{(ACCUMULATOR_WIDTH-MEMBRANE_WIDTH){1'b0}}, output_leaked};
        if (fast_spike)
            output_sum = output_sum + OUTPUT_FAST_WEIGHT_VALUE;
        if (pressure_spike)
            output_sum = output_sum + OUTPUT_PRESSURE_WEIGHT_VALUE;
        output_integrated = (output_sum > MAX_POTENTIAL_EXTENDED)
            ? MAX_POTENTIAL : output_sum[MEMBRANE_WIDTH-1:0];
        output_spike_next = (output_integrated >= OUTPUT_THRESHOLD_VALUE);
        output_membrane_next = output_spike_next
            ? output_integrated - OUTPUT_THRESHOLD_VALUE : output_integrated;
        output_activity_next = output_integrated;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fast_membrane <= '0;
            pressure_membrane <= '0;
            output_membrane <= '0;
            prediction_valid <= 1'b0;
            predicted_congestion <= 1'b0;
            prediction_activity <= '0;
        end else begin
            prediction_valid <= feature_valid;
            if (feature_valid) begin
                fast_membrane <= fast_membrane_next;
                pressure_membrane <= pressure_membrane_next;
                output_membrane <= output_membrane_next;
                predicted_congestion <= output_spike_next;
                prediction_activity <= output_activity_next;
            end
        end
    end
endmodule
