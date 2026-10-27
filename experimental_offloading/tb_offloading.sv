`timescale 1ns/1ps

module tb_offloading;
    localparam int PACKET_WIDTH = 48;
    localparam int DUT_TIMEOUT_CYCLES = 4;

    localparam int MON_IDLE = 0;
    localparam int MON_WAIT = 1;
    localparam int MON_EXPECT_COMMIT = 2;
    localparam int MON_EXPECT_FAILURE = 3;

    logic clk = 1'b0;
    logic rst_n = 1'b0;

    logic [7:0] congestion_level = '0;
    logic candidate_valid = 1'b0;
    logic [3:0] candidate_id = '0;
    logic candidate_eligible = 1'b0;
    logic candidate_route_legal = 1'b0;
    logic downstream_capacity_ok = 1'b0;
    logic [PACKET_WIDTH-1:0] candidate_packet = '0;
    logic congestion_active;
    logic offload_available;
    logic transfer_request_valid;
    logic [PACKET_WIDTH-1:0] transfer_request_packet;
    logic receiver_accept = 1'b0;
    logic receiver_reject = 1'b0;
    logic cancel = 1'b0;
    logic sender_commit;
    logic transfer_failed;

    logic [7:0] selector_congestion = '0;
    logic [7:0] selector_threshold = 8'd8;
    logic [2:0] priority_cutoff = 3'd4;
    logic [2:0] candidate_valids = '0;
    logic [2:0][2:0] priorities_low_first = '0;
    logic [2:0][2:0] priorities_high_first = '0;
    logic [2:0] routes_legal = '0;
    logic [2:0] capacities = '0;
    logic [2:0] candidate_serviced = '0;
    logic selected_valid_low;
    logic [1:0] selected_index_low;
    logic [2:0] selected_onehot_low;
    logic selected_valid_high;
    logic [1:0] selected_index_high;
    logic [2:0] selected_onehot_high;
    logic selected_valid_aging;
    logic [1:0] selected_index_aging;
    logic [2:0] selected_onehot_aging;

    logic [0:0] route_reset_valid = '0;
    logic [2:0] route_reset_priority = '0;
    logic [0:0] route_reset_legal = '0;
    logic [0:0] route_reset_capacity = '0;
    logic route_reset_selected_valid;
    logic [0:0] route_reset_selected_index;
    logic [0:0] route_reset_selected_onehot;

    logic [0:0] valid_reset_valid = '0;
    logic [2:0] valid_reset_priority = '0;
    logic [0:0] valid_reset_legal = '0;
    logic [0:0] valid_reset_capacity = '0;
    logic valid_reset_selected_valid;
    logic [0:0] valid_reset_selected_index;
    logic [0:0] valid_reset_selected_onehot;

    logic [0:0] boundary_congestion = '0;
    logic boundary_accept = 1'b0;
    logic boundary_reject = 1'b0;
    logic boundary_cancel = 1'b0;
    logic boundary_candidate_valid = 1'b0;
    logic [0:0] boundary_candidate_id = '0;
    logic boundary_eligible = 1'b0;
    logic boundary_route_legal = 1'b0;
    logic boundary_capacity = 1'b0;
    logic [7:0] boundary_packet = '0;
    logic boundary_congestion_active;
    logic boundary_available;
    logic boundary_request_valid;
    logic [7:0] boundary_request_packet;
    logic boundary_commit;
    logic boundary_failed;
    logic [0:0] boundary_selector_valid = '0;
    logic [0:0][0:0] boundary_priority = '0;
    logic [0:0] boundary_route_vector = '0;
    logic [0:0] boundary_capacity_vector = '0;
    logic [0:0] boundary_serviced = '0;
    logic boundary_selected_valid;
    logic [0:0] boundary_selected_index;
    logic [0:0] boundary_selected_onehot;

    integer checks = 0;
    integer monitor_state = MON_IDLE;
    integer monitor_wait_count = 0;
    logic [PACKET_WIDTH-1:0] monitor_packet = '0;

    always #5 clk = ~clk;

    congestion_offload_controller #(
        .PACKET_WIDTH(PACKET_WIDTH),
        .CANDIDATE_ID_WIDTH(4),
        .LEVEL_WIDTH(8),
        .ASSERT_THRESHOLD(8),
        .RECOVERY_THRESHOLD(3),
        .CONGESTION_PERSIST_CYCLES(3),
        .RECOVERY_PERSIST_CYCLES(2),
        .TRANSFER_TIMEOUT_CYCLES(DUT_TIMEOUT_CYCLES),
        .MAX_OFFLOAD_ATTEMPTS(2)
    ) dut (
        .clk,
        .rst_n,
        .congestion_level,
        .candidate_valid,
        .candidate_id,
        .candidate_eligible,
        .candidate_route_legal,
        .downstream_capacity_ok,
        .candidate_packet,
        .congestion_active,
        .offload_available,
        .transfer_request_valid,
        .transfer_request_packet,
        .receiver_accept,
        .receiver_reject,
        .cancel,
        .sender_commit,
        .transfer_failed
    );

    priority_offload_selector #(
        .NUM_CANDIDATES(3),
        .PRIORITY_WIDTH(3),
        .LEVEL_WIDTH(8),
        .AGE_LIMIT_CYCLES(16),
        .HIGHER_VALUE_IS_HIGHER_PRIORITY(1'b0)
    ) selector_low_numeric_urgent (
        .clk,
        .rst_n,
        .congestion_level(selector_congestion),
        .congestion_threshold(selector_threshold),
        .lowest_offload_priority(priority_cutoff),
        .candidate_valid(candidate_valids),
        .candidate_priority(priorities_low_first),
        .candidate_route_legal(routes_legal),
        .candidate_capacity_ok(capacities),
        .candidate_serviced,
        .selected_valid(selected_valid_low),
        .selected_index(selected_index_low),
        .selected_onehot(selected_onehot_low)
    );

    priority_offload_selector #(
        .NUM_CANDIDATES(3),
        .PRIORITY_WIDTH(3),
        .LEVEL_WIDTH(8),
        .AGE_LIMIT_CYCLES(16),
        .HIGHER_VALUE_IS_HIGHER_PRIORITY(1'b1)
    ) selector_high_numeric_urgent (
        .clk,
        .rst_n,
        .congestion_level(selector_congestion),
        .congestion_threshold(selector_threshold),
        .lowest_offload_priority(priority_cutoff),
        .candidate_valid(candidate_valids),
        .candidate_priority(priorities_high_first),
        .candidate_route_legal(routes_legal),
        .candidate_capacity_ok(capacities),
        .candidate_serviced,
        .selected_valid(selected_valid_high),
        .selected_index(selected_index_high),
        .selected_onehot(selected_onehot_high)
    );

    priority_offload_selector #(
        .NUM_CANDIDATES(3),
        .PRIORITY_WIDTH(3),
        .LEVEL_WIDTH(8),
        .AGE_LIMIT_CYCLES(3),
        .HIGHER_VALUE_IS_HIGHER_PRIORITY(1'b0)
    ) selector_aging (
        .clk,
        .rst_n,
        .congestion_level(selector_congestion),
        .congestion_threshold(selector_threshold),
        .lowest_offload_priority(priority_cutoff),
        .candidate_valid(candidate_valids),
        .candidate_priority(priorities_low_first),
        .candidate_route_legal(routes_legal),
        .candidate_capacity_ok(capacities),
        .candidate_serviced,
        .selected_valid(selected_valid_aging),
        .selected_index(selected_index_aging),
        .selected_onehot(selected_onehot_aging)
    );

    priority_offload_selector #(
        .NUM_CANDIDATES(1),
        .PRIORITY_WIDTH(3),
        .LEVEL_WIDTH(8),
        .AGE_LIMIT_CYCLES(3),
        .HIGHER_VALUE_IS_HIGHER_PRIORITY(1'b0)
    ) selector_route_invalidation (
        .clk,
        .rst_n,
        .congestion_level(selector_congestion),
        .congestion_threshold(selector_threshold),
        .lowest_offload_priority(priority_cutoff),
        .candidate_valid(route_reset_valid),
        .candidate_priority(route_reset_priority),
        .candidate_route_legal(route_reset_legal),
        .candidate_capacity_ok(route_reset_capacity),
        .candidate_serviced(1'b0),
        .selected_valid(route_reset_selected_valid),
        .selected_index(route_reset_selected_index),
        .selected_onehot(route_reset_selected_onehot)
    );

    priority_offload_selector #(
        .NUM_CANDIDATES(1),
        .PRIORITY_WIDTH(3),
        .LEVEL_WIDTH(8),
        .AGE_LIMIT_CYCLES(3),
        .HIGHER_VALUE_IS_HIGHER_PRIORITY(1'b0)
    ) selector_valid_invalidation (
        .clk,
        .rst_n,
        .congestion_level(selector_congestion),
        .congestion_threshold(selector_threshold),
        .lowest_offload_priority(priority_cutoff),
        .candidate_valid(valid_reset_valid),
        .candidate_priority(valid_reset_priority),
        .candidate_route_legal(valid_reset_legal),
        .candidate_capacity_ok(valid_reset_capacity),
        .candidate_serviced(1'b0),
        .selected_valid(valid_reset_selected_valid),
        .selected_index(valid_reset_selected_index),
        .selected_onehot(valid_reset_selected_onehot)
    );

    congestion_offload_controller #(
        .PACKET_WIDTH(8),
        .CANDIDATE_ID_WIDTH(1),
        .LEVEL_WIDTH(1),
        .ASSERT_THRESHOLD(1),
        .RECOVERY_THRESHOLD(0),
        .CONGESTION_PERSIST_CYCLES(1),
        .RECOVERY_PERSIST_CYCLES(1),
        .TRANSFER_TIMEOUT_CYCLES(1),
        .MAX_OFFLOAD_ATTEMPTS(1)
    ) boundary_controller (
        .clk,
        .rst_n,
        .congestion_level(boundary_congestion),
        .candidate_valid(boundary_candidate_valid),
        .candidate_id(boundary_candidate_id),
        .candidate_eligible(boundary_eligible),
        .candidate_route_legal(boundary_route_legal),
        .downstream_capacity_ok(boundary_capacity),
        .candidate_packet(boundary_packet),
        .congestion_active(boundary_congestion_active),
        .offload_available(boundary_available),
        .transfer_request_valid(boundary_request_valid),
        .transfer_request_packet(boundary_request_packet),
        .receiver_accept(boundary_accept),
        .receiver_reject(boundary_reject),
        .cancel(boundary_cancel),
        .sender_commit(boundary_commit),
        .transfer_failed(boundary_failed)
    );

    priority_offload_selector #(
        .NUM_CANDIDATES(1),
        .PRIORITY_WIDTH(1),
        .LEVEL_WIDTH(1),
        .AGE_LIMIT_CYCLES(1),
        .HIGHER_VALUE_IS_HIGHER_PRIORITY(1'b1)
    ) boundary_selector (
        .clk,
        .rst_n,
        .congestion_level(1'b1),
        .congestion_threshold(1'b1),
        .lowest_offload_priority(1'b0),
        .candidate_valid(boundary_selector_valid),
        .candidate_priority(boundary_priority),
        .candidate_route_legal(boundary_route_vector),
        .candidate_capacity_ok(boundary_capacity_vector),
        .candidate_serviced(boundary_serviced),
        .selected_valid(boundary_selected_valid),
        .selected_index(boundary_selected_index),
        .selected_onehot(boundary_selected_onehot)
    );

    task automatic check(input logic condition, input string message);
        begin
            checks = checks + 1;
            if (condition !== 1'b1) begin
                $error("CHECK FAILED: %s at time %0t", message, $time);
                $fatal(1);
            end
        end
    endtask

    task automatic step;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    task automatic reset_all;
        begin
            rst_n = 1'b0;
            step();
            step();
            rst_n = 1'b1;
            step();
        end
    endtask

    task automatic check_selector_outputs;
        integer count_low;
        integer count_high;
        integer count_aging;
        begin
            count_low = 0;
            count_high = 0;
            count_aging = 0;
            for (int i = 0; i < 3; i++) begin
                if (selected_onehot_low[i]) count_low = count_low + 1;
                if (selected_onehot_high[i]) count_high = count_high + 1;
                if (selected_onehot_aging[i]) count_aging = count_aging + 1;
            end
            check(count_low <= 1 && selected_valid_low == (count_low == 1),
                  "low-first selector output is one-hot-or-zero");
            check(count_high <= 1 && selected_valid_high == (count_high == 1),
                  "high-first selector output is one-hot-or-zero");
            check(count_aging <= 1 && selected_valid_aging == (count_aging == 1),
                  "aging selector output is one-hot-or-zero");
            if (selected_valid_low)
                check(selected_index_low < 3, "low-first index is in range");
            if (selected_valid_high)
                check(selected_index_high < 3, "high-first index is in range");
            if (selected_valid_aging)
                check(selected_index_aging < 3, "aging index is in range");
        end
    endtask

    task automatic assert_selector_3(
        input logic selected_valid,
        input logic [1:0] selected_index,
        input logic [2:0] selected_onehot,
        input logic [2:0] valid_vector,
        input logic [2:0] legal_vector,
        input logic [2:0] capacity_vector
    );
        integer one_count;
        begin
            one_count = 0;
            for (int i = 0; i < 3; i++)
                if (selected_onehot[i])
                    one_count = one_count + 1;

            if (one_count > 1 || selected_valid !== (one_count == 1))
                $fatal(1, "Selector output is not one-hot-or-zero");
            if (selected_valid) begin
                if (selected_index >= 3)
                    $fatal(1, "Selector produced an out-of-range index");
                if (!valid_vector[selected_index]
                    || !legal_vector[selected_index]
                    || !capacity_vector[selected_index])
                    $fatal(1, "Selector chose an invalid, illegal, or full candidate");
                if (selector_congestion < selector_threshold)
                    $fatal(1, "Selector chose a candidate below congestion threshold");
                if (!selected_onehot[selected_index])
                    $fatal(1, "Selector index does not match one-hot output");
            end
        end
    endtask

    task automatic ensure_congestion_active;
        begin
            congestion_level = 8'd8;
            if (!congestion_active) begin
                repeat (3) step();
            end
            check(congestion_active, "congestion becomes active after persistence");
        end
    endtask

    task automatic prepare_packet(
        input logic [3:0] id,
        input logic [PACKET_WIDTH-1:0] packet
    );
        begin
            ensure_congestion_active();
            candidate_valid = 1'b1;
            candidate_id = id;
            candidate_packet = packet;
            candidate_eligible = 1'b1;
            candidate_route_legal = 1'b1;
            downstream_capacity_ok = 1'b1;
        end
    endtask

    initial begin
        boundary_accept = 1'b0;
        boundary_reject = 1'b0;
        boundary_cancel = 1'b0;
        reset_all();

        check(!congestion_active && !transfer_request_valid && !sender_commit,
              "reset initializes controller idle");
        check(!offload_available, "no offer without congestion");

        candidate_valid = 1'b1;
        candidate_id = 4'd1;
        candidate_eligible = 1'b0;
        candidate_route_legal = 1'b1;
        downstream_capacity_ok = 1'b1;
        congestion_level = 8'd8;
        step();
        step();
        check(!congestion_active, "assertion persistence prevents early congestion");
        congestion_level = 8'd7;
        step();
        congestion_level = 8'd8;
        step();
        step();
        check(!congestion_active, "interrupted high samples restart persistence");
        step();
        check(congestion_active, "three consecutive high samples assert congestion");
        check(!offload_available, "ineligible candidate cannot be offered");

        candidate_eligible = 1'b1;
        candidate_route_legal = 1'b0;
        #1;
        check(!offload_available, "illegal route blocks an offer");
        candidate_route_legal = 1'b1;
        downstream_capacity_ok = 1'b0;
        #1;
        check(!offload_available, "insufficient capacity blocks an offer");
        downstream_capacity_ok = 1'b1;
        #1;
        check(offload_available, "eligible legal candidate with capacity can be offered");
        candidate_packet = 48'h1234_5678_9abc;
        step();
        check(transfer_request_valid, "controller launches transfer offer");
        check(transfer_request_packet == 48'h1234_5678_9abc,
              "offer carries snapshotted payload");

        candidate_packet = 48'hffff_ffff_ffff;
        candidate_id = 4'd9;
        candidate_valid = 1'b0;
        candidate_route_legal = 1'b0;
        downstream_capacity_ok = 1'b0;
        step();
        check(transfer_request_valid, "candidate_valid drop does not cancel pending request");
        check(transfer_request_packet == 48'h1234_5678_9abc,
              "pending payload remains stable despite candidate changes");
        receiver_accept = 1'b1;
        step();
        receiver_accept = 1'b0;
        check(sender_commit && !transfer_failed && !transfer_request_valid,
              "acceptance produces commit without failure");
        step();
        check(!sender_commit, "commit is a single-cycle indication");

        congestion_level = 8'd4;
        step();
        check(congestion_active, "hysteresis band retains congestion state");
        congestion_level = 8'd3;
        step();
        check(congestion_active, "recovery persistence prevents early clearing");
        step();
        check(!congestion_active, "two consecutive low samples clear congestion");

        // Reject dominates accept, consumes an attempt, and does not commit.
        prepare_packet(4'd2, 48'h2222_aaaa_0001);
        step();
        check(transfer_request_valid, "identity 2 starts its first attempt");
        receiver_reject = 1'b1;
        receiver_accept = 1'b1;
        step();
        receiver_reject = 1'b0;
        receiver_accept = 1'b0;
        check(transfer_failed && !sender_commit,
              "rejection wins over simultaneous acceptance");
        step();
        step();
        check(transfer_request_valid, "same identity may use its remaining retry");

        // Cancel also dominates accept; the second failed try exhausts ID 2.
        cancel = 1'b1;
        receiver_accept = 1'b1;
        step();
        cancel = 1'b0;
        receiver_accept = 1'b0;
        check(transfer_failed && !sender_commit,
              "cancellation wins over simultaneous acceptance");
        step();
        check(!offload_available,
              "failed attempts consume the identity retry budget");

        // A different identity can start even though valid remains asserted.
        candidate_id = 4'd3;
        candidate_packet = 48'h3333_bbbb_0002;
        #1;
        check(offload_available, "new candidate ID receives a fresh retry budget");
        step();
        check(transfer_request_valid, "new identity starts a new transfer");
        repeat (3) begin
            step();
            check(transfer_request_valid,
                  "timeout counter retains request before its boundary cycle");
        end
        receiver_accept = 1'b1;
        step();
        receiver_accept = 1'b0;
        check(sender_commit && !transfer_failed,
              "acceptance on timeout boundary wins over timeout");
        step();
        check(!offload_available,
              "successful transfer exhausts the tracked identity budget");

        // Four complete request cycles are allowed for timeout=4.
        candidate_id = 4'd4;
        candidate_packet = 48'h4444_cccc_0003;
        step();
        check(transfer_request_valid, "identity 4 starts timeout test");
        repeat (3) begin
            step();
            check(transfer_request_valid, "request remains valid before cycle four");
        end
        step();
        check(transfer_failed && !sender_commit && !transfer_request_valid,
              "timeout occurs after exactly four unanswered request cycles");
        step();

        // Timeout exhausted ID 4, but ID 5 is independently eligible.
        candidate_id = 4'd5;
        candidate_packet = 48'h5555_dddd_0004;
        #1;
        check(offload_available, "new ID is not blocked by previous ID exhaustion");
        step();
        check(transfer_request_valid, "new ID launches after previous timeout");
        candidate_valid = 1'b0;
        step();
        check(transfer_request_valid
              && transfer_request_packet == 48'h5555_dddd_0004,
              "pending transaction survives source valid deassertion");
        receiver_accept = 1'b1;
        step();
        receiver_accept = 1'b0;
        check(sender_commit, "acceptance commits even if source valid fell");
        step();
        step();
        candidate_valid = 1'b1;
        candidate_id = 4'd5;
        candidate_packet = 48'h5555_dddd_0004;
        candidate_route_legal = 1'b1;
        downstream_capacity_ok = 1'b1;
        #1;
        check(offload_available,
              "idle valid deassertion clears budget before candidate ID reuse");
        step();
        check(transfer_request_valid,
              "reused ID starts with a fresh budget after idle deassertion");
        cancel = 1'b1;
        step();
        cancel = 1'b0;
        check(transfer_failed && !sender_commit,
              "reused-ID attempt can terminate without ownership commit");
        step();
        candidate_valid = 1'b0;
        step();

        // Reset while a request is outstanding asynchronously aborts control
        // state without claiming a commit.
        prepare_packet(4'd6, 48'h6666_eeee_0005);
        step();
        check(transfer_request_valid, "pending-reset test started transfer");
        #2 rst_n = 1'b0;
        #1;
        check(!transfer_request_valid && !sender_commit && !transfer_failed,
              "reset clears a pending transfer without commit");
        step();
        rst_n = 1'b1;
        step();

        // Selector priority/capacity/route gates and both encodings.
        selector_congestion = 8'd8;
        candidate_valids = 3'b111;
        routes_legal = 3'b111;
        capacities = 3'b111;
        priorities_low_first[0] = 3'd1;
        priorities_low_first[1] = 3'd5;
        priorities_low_first[2] = 3'd7;
        priorities_high_first[0] = 3'd7;
        priorities_high_first[1] = 3'd3;
        priorities_high_first[2] = 3'd1;
        #1;
        check_selector_outputs();
        check(selected_valid_low && selected_index_low == 2,
              "low-numeric-urgent encoding selects least urgent eligible packet");
        check(selected_valid_high && selected_index_high == 2,
              "high-numeric-urgent encoding selects least urgent eligible packet");
        capacities[2] = 1'b0;
        #1;
        check(selected_index_low == 1 && selected_index_high == 1,
              "capacity gate removes a candidate in both encodings");
        routes_legal[1] = 1'b0;
        #1;
        check(!selected_valid_low && !selected_valid_high,
              "route legality gates both priority encodings");
        routes_legal[1] = 1'b1;
        capacities[2] = 1'b1;
        selector_congestion = 0;
        #1;
        check(!selected_valid_low && !selected_valid_high,
              "congestion threshold gates both priority encodings");

        // Equal-priority round robin and simultaneous service handling.
        selector_congestion = 8'd8;
        priorities_low_first = {3{3'd5}};
        priorities_high_first = {3{3'd2}};
        #1;
        check(selected_index_low == 0 && selected_index_high == 0,
              "initial equal-priority tie begins at candidate zero");
        candidate_serviced = 3'b001;
        step();
        candidate_serviced = '0;
        #1;
        check(selected_index_low == 1 && selected_index_high == 1,
              "service rotates equal-priority selection to candidate one");
        candidate_serviced = 3'b010;
        step();
        candidate_serviced = '0;
        #1;
        check(selected_index_low == 2 && selected_index_high == 2,
              "round robin continues to candidate two");
        candidate_serviced = 3'b100;
        step();
        candidate_serviced = '0;
        #1;
        check(selected_index_low == 0 && selected_index_high == 0,
              "round robin wraps at candidate count");
        candidate_serviced = 3'b011;
        step();
        candidate_serviced = '0;
        #1;
        check(selected_index_low == 0 && selected_index_high == 0,
              "multiple service bits are ignored without pointer movement");

        // Directed stale-best-distance regression: after servicing candidate
        // zero, the pointer is one. Candidate zero first becomes provisional,
        // candidate one replaces it on priority, and candidate two ties.
        // Correct bookkeeping keeps candidate one (distance zero) ahead of
        // candidate two (distance one) in both priority encodings.
        candidate_serviced = 3'b001;
        step();
        candidate_serviced = '0;
        priorities_low_first[0] = 3'd4;
        priorities_low_first[1] = 3'd5;
        priorities_low_first[2] = 3'd5;
        priorities_high_first[0] = 3'd4;
        priorities_high_first[1] = 3'd3;
        priorities_high_first[2] = 3'd3;
        #1;
        check(selected_index_low == 1,
              "stale-distance regression keeps best round-robin tie in low-first mode");
        check(selected_index_high == 1,
              "stale-distance regression keeps best round-robin tie in high-first mode");

        // Aging overrides cutoff for both encodings and saturates until
        // serviced or invalidated. Candidate zero is deliberately cutoff-
        // ineligible; candidate one is ordinarily eligible.
        reset_all();
        selector_congestion = 8'd8;
        candidate_valids = 3'b011;
        routes_legal = 3'b111;
        capacities = 3'b111;
        priorities_low_first[0] = 3'd1;
        priorities_low_first[1] = 3'd5;
        priorities_low_first[2] = 3'd0;
        priorities_high_first[0] = 3'd7;
        priorities_high_first[1] = 3'd1;
        priorities_high_first[2] = 3'd7;
        priority_cutoff = 3'd4;
        #1;
        check(selected_index_low == 1 && selected_index_high == 1
              && selected_index_aging == 1,
              "unaged candidates outside cutoff are protected");
        repeat (3) step();
        #1;
        check(selected_index_aging == 0 && selected_index_low == 1,
              "bounded aging overrides cutoff only in aging-enabled selector");
        repeat (8) step();
        #1;
        check(selected_index_aging == 0,
              "saturated aged candidate remains promoted without counter wrap");
        candidate_serviced = 3'b011;
        step();
        candidate_serviced = '0;
        #1;
        check(selected_index_aging == 0,
              "invalid multi-service vector does not clear aged state");

        capacities[0] = 1'b0;
        #1;
        check(selected_index_aging == 1,
              "insufficient capacity invalidates and de-ages candidate");
        repeat (4) step();
        capacities[0] = 1'b1;
        #1;
        check(selected_index_aging == 1,
              "restored capacity does not restore prior age");
        repeat (2) step();
        #1;
        check(selected_index_aging == 1,
              "candidate does not promote before full aging interval");
        step();
        #1;
        check(selected_index_aging == 0,
              "candidate promotes again after a fresh aging interval");

        selector_congestion = 0;
        step();
        #1;
        check(!selected_valid_aging, "congestion loss invalidates selector eligibility");
        selector_congestion = 8'd8;
        candidate_valids = 3'b001;
        repeat (2) step();
        #1;
        check(!selected_valid_aging,
              "congestion loss resets age instead of retaining promotion");
        step();
        #1;
        check(selected_valid_aging && selected_index_aging == 0,
              "candidate can age again after congestion resumes");
        candidate_valids = '0;
        #1;
        check(!selected_valid_aging, "invalid candidate produces zero selection");

        // Route invalidation clears the age after its next sampling edge.
        // The counter advances once per eligible posedge, so AGE_LIMIT=3
        // promotes on the third edge after eligibility is restored.
        reset_all();
        selector_congestion = 8'd8;
        route_reset_valid = 1'b1;
        route_reset_priority = 3'd1;
        route_reset_legal = 1'b1;
        route_reset_capacity = 1'b1;
        #1;
        check(!route_reset_selected_valid,
              "route-invalidation candidate starts below aging threshold");
        repeat (2) step();
        #1;
        check(!route_reset_selected_valid,
              "route-invalidation candidate is not promoted before edge three");
        step();
        check(route_reset_selected_valid && route_reset_selected_index == 0,
              "route-invalidation candidate promotes at the third eligible edge");
        route_reset_legal = 1'b0;
        #1;
        check(!route_reset_selected_valid,
              "route-illegal candidate is immediately unselectable");
        step();
        route_reset_legal = 1'b1;
        #1;
        check(!route_reset_selected_valid,
              "route legality restoration does not restore stale age");
        repeat (2) step();
        #1;
        check(!route_reset_selected_valid,
              "route-reset candidate waits two full eligible edges");
        step();
        check(route_reset_selected_valid && route_reset_selected_index == 0,
              "route-reset candidate promotes after a complete new interval");

        // Candidate-valid invalidation is independent of route invalidation.
        reset_all();
        selector_congestion = 8'd8;
        valid_reset_valid = 1'b1;
        valid_reset_priority = 3'd1;
        valid_reset_legal = 1'b1;
        valid_reset_capacity = 1'b1;
        #1;
        check(!valid_reset_selected_valid,
              "validity-invalidation candidate starts below aging threshold");
        repeat (2) step();
        #1;
        check(!valid_reset_selected_valid,
              "validity-invalidation candidate is not promoted before edge three");
        step();
        check(valid_reset_selected_valid && valid_reset_selected_index == 0,
              "validity-invalidation candidate promotes at the third eligible edge");
        valid_reset_valid = 1'b0;
        #1;
        check(!valid_reset_selected_valid,
              "invalid candidate is immediately unselectable");
        step();
        valid_reset_valid = 1'b1;
        #1;
        check(!valid_reset_selected_valid,
              "validity restoration does not restore stale age");
        repeat (2) step();
        #1;
        check(!valid_reset_selected_valid,
              "valid-reset candidate waits two full eligible edges");
        step();
        check(valid_reset_selected_valid && valid_reset_selected_index == 0,
              "valid-reset candidate promotes after a complete new interval");

        // Minimum one-candidate selector and controller parameter values.
        boundary_selector_valid = 1'b1;
        boundary_priority[0] = 1'b0;
        boundary_route_vector = 1'b1;
        boundary_capacity_vector = 1'b1;
        #1;
        check(boundary_selected_valid && boundary_selected_index == 0
              && boundary_selected_onehot == 1'b1,
              "NUM_CANDIDATES=1 selects index zero one-hot");
        boundary_selector_valid = 1'b0;
        #1;
        check(!boundary_selected_valid && boundary_selected_onehot == 1'b0,
              "one-candidate selector returns zero when invalid");

        boundary_congestion = 1'b1;
        boundary_candidate_valid = 1'b1;
        boundary_candidate_id = 1'b0;
        boundary_eligible = 1'b1;
        boundary_route_legal = 1'b1;
        boundary_capacity = 1'b1;
        boundary_packet = 8'h5a;
        step();
        check(boundary_congestion_active && !boundary_request_valid,
              "minimum persistence asserts congestion at first sample");
        step();
        check(boundary_request_valid && boundary_request_packet == 8'h5a,
              "minimum-parameter controller launches request");
        step();
        check(boundary_failed && !boundary_commit,
              "timeout=1 expires after one unanswered request cycle");
        step();
        boundary_candidate_valid = 1'b0;
        step();
        boundary_candidate_valid = 1'b1;
        boundary_candidate_id = 1'b1;
        step();
        check(boundary_request_valid,
              "new one-bit candidate identity gets a fresh attempt budget");
        boundary_accept = 1'b1;
        step();
        boundary_accept = 1'b0;
        check(boundary_commit && !boundary_failed,
              "acceptance on timeout=1 boundary commits");
        step();
        check(!boundary_commit, "boundary commit is one cycle");

        check_selector_outputs();
        $display("PASS: %0d checks completed", checks);
        $finish;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            monitor_state = MON_IDLE;
            monitor_wait_count = 0;
            monitor_packet = '0;
        end else begin
            case (monitor_state)
                MON_IDLE: begin
                    if (transfer_request_valid || sender_commit || transfer_failed)
                        $fatal(1, "Unexpected transfer output while reference model is idle");

                    if (offload_available) begin
                        monitor_packet = candidate_packet;
                        monitor_wait_count = 0;
                        monitor_state = MON_WAIT;
                    end
                end

                MON_WAIT: begin
                    if (!transfer_request_valid)
                        $fatal(1, "Pending request disappeared before a sampled terminal event");
                    if (transfer_request_packet !== monitor_packet)
                        $fatal(1, "Pending request payload changed before a terminal event");
                    if (sender_commit || transfer_failed)
                        $fatal(1, "Commit/failure asserted before its registered response cycle");

                    if (cancel || receiver_reject) begin
                        monitor_state = MON_EXPECT_FAILURE;
                        monitor_wait_count = 0;
                    end else if (receiver_accept) begin
                        monitor_state = MON_EXPECT_COMMIT;
                        monitor_wait_count = 0;
                    end else if (monitor_wait_count == DUT_TIMEOUT_CYCLES - 1) begin
                        monitor_state = MON_EXPECT_FAILURE;
                        monitor_wait_count = 0;
                    end else begin
                        monitor_wait_count = monitor_wait_count + 1;
                    end
                end

                MON_EXPECT_COMMIT: begin
                    if (transfer_request_valid || !sender_commit || transfer_failed)
                        $fatal(1, "Acceptance must produce exactly one commit response cycle");
                    monitor_state = MON_IDLE;
                    monitor_wait_count = 0;
                end

                MON_EXPECT_FAILURE: begin
                    if (transfer_request_valid || sender_commit || !transfer_failed)
                        $fatal(1, "Reject/cancel/timeout must produce exactly one failure response cycle");
                    monitor_state = MON_IDLE;
                    monitor_wait_count = 0;
                end

                default:
                    $fatal(1, "Invalid protocol reference-model state");
            endcase

            if (sender_commit && transfer_failed)
                $fatal(1, "Commit and failure asserted together");
            if (boundary_commit && boundary_failed)
                $fatal(1, "Boundary controller commit and failure overlap");
        end
    end

    always @(negedge clk) begin
        #1;
        if (rst_n) begin
            assert_selector_3(selected_valid_low, selected_index_low,
                selected_onehot_low, candidate_valids, routes_legal, capacities);
            assert_selector_3(selected_valid_high, selected_index_high,
                selected_onehot_high, candidate_valids, routes_legal, capacities);
            assert_selector_3(selected_valid_aging, selected_index_aging,
                selected_onehot_aging, candidate_valids, routes_legal, capacities);

            if (boundary_selected_valid !== (boundary_selected_onehot == 1'b1))
                $fatal(1, "One-candidate selector output is not one-hot-or-zero");
            if (boundary_selected_valid
                && (!boundary_selector_valid[0]
                    || !boundary_route_vector[0]
                    || !boundary_capacity_vector[0]
                    || boundary_selected_index != 0))
                $fatal(1, "One-candidate selector violated candidate gates");

            if (route_reset_selected_valid
                !== (route_reset_selected_onehot == 1'b1))
                $fatal(1, "Route-invalidation selector is not one-hot-or-zero");
            if (route_reset_selected_valid
                && (!route_reset_valid[0] || !route_reset_legal[0]
                    || !route_reset_capacity[0]
                    || selector_congestion < selector_threshold))
                $fatal(1, "Route-invalidation selector bypassed a required gate");
            if (valid_reset_selected_valid
                !== (valid_reset_selected_onehot == 1'b1))
                $fatal(1, "Validity-invalidation selector is not one-hot-or-zero");
            if (valid_reset_selected_valid
                && (!valid_reset_valid[0] || !valid_reset_legal[0]
                    || !valid_reset_capacity[0]
                    || selector_congestion < selector_threshold))
                $fatal(1, "Validity-invalidation selector bypassed a required gate");
        end
    end
endmodule
