`timescale 1ns/1ps

module congestion_offload_controller #(
    parameter int PACKET_WIDTH = 48,
    parameter int CANDIDATE_ID_WIDTH = 16,
    parameter int LEVEL_WIDTH = 8,
    parameter int ASSERT_THRESHOLD = 8,
    parameter int RECOVERY_THRESHOLD = 3,
    parameter int CONGESTION_PERSIST_CYCLES = 4,
    parameter int RECOVERY_PERSIST_CYCLES = 4,
    parameter int TRANSFER_TIMEOUT_CYCLES = 16,
    parameter int MAX_OFFLOAD_ATTEMPTS = 3,
    parameter int ATTEMPT_COUNT_WIDTH =
        (MAX_OFFLOAD_ATTEMPTS > 1) ? $clog2(MAX_OFFLOAD_ATTEMPTS + 1) : 1
) (
    input  logic                         clk,
    input  logic                         rst_n,
    input  logic [((LEVEL_WIDTH > 0) ? LEVEL_WIDTH : 1)-1:0] congestion_level,

    input  logic                         candidate_valid,
    input  logic [((CANDIDATE_ID_WIDTH > 0) ? CANDIDATE_ID_WIDTH : 1)-1:0] candidate_id,
    input  logic                         candidate_eligible,
    input  logic                         candidate_route_legal,
    input  logic                         downstream_capacity_ok,
    input  logic [((PACKET_WIDTH > 0) ? PACKET_WIDTH : 1)-1:0] candidate_packet,

    output logic                         congestion_active,
    output logic                         offload_available,
    output logic                         transfer_request_valid,
    output logic [((PACKET_WIDTH > 0) ? PACKET_WIDTH : 1)-1:0] transfer_request_packet,
    input  logic                         receiver_accept,
    input  logic                         receiver_reject,
    input  logic                         cancel,
    output logic                         sender_commit,
    output logic                         transfer_failed
);

    localparam int PACKET_STORAGE_WIDTH = (PACKET_WIDTH > 0) ? PACKET_WIDTH : 1;
    localparam int ID_STORAGE_WIDTH =
        (CANDIDATE_ID_WIDTH > 0) ? CANDIDATE_ID_WIDTH : 1;
    localparam int LEVEL_STORAGE_WIDTH = (LEVEL_WIDTH > 0) ? LEVEL_WIDTH : 1;
    localparam int ATTEMPT_STORAGE_WIDTH =
        (ATTEMPT_COUNT_WIDTH > 0) ? ATTEMPT_COUNT_WIDTH : 1;
    localparam int ASSERT_COUNT_WIDTH =
        (CONGESTION_PERSIST_CYCLES > 1) ? $clog2(CONGESTION_PERSIST_CYCLES + 1) : 1;
    localparam int RECOVERY_COUNT_WIDTH =
        (RECOVERY_PERSIST_CYCLES > 1) ? $clog2(RECOVERY_PERSIST_CYCLES + 1) : 1;
    localparam int TIMEOUT_COUNT_WIDTH =
        (TRANSFER_TIMEOUT_CYCLES > 1) ? $clog2(TRANSFER_TIMEOUT_CYCLES + 1) : 1;
    localparam int REQUIRED_ATTEMPT_WIDTH =
        (MAX_OFFLOAD_ATTEMPTS > 1) ? $clog2(MAX_OFFLOAD_ATTEMPTS + 1) : 1;

    localparam logic [ASSERT_COUNT_WIDTH-1:0] ASSERT_COUNT_LIMIT =
        CONGESTION_PERSIST_CYCLES - 1;
    localparam logic [RECOVERY_COUNT_WIDTH-1:0] RECOVERY_COUNT_LIMIT =
        RECOVERY_PERSIST_CYCLES - 1;
    localparam logic [TIMEOUT_COUNT_WIDTH-1:0] TIMEOUT_COUNT_LIMIT =
        TRANSFER_TIMEOUT_CYCLES - 1;
    localparam logic [ATTEMPT_STORAGE_WIDTH-1:0] MAX_ATTEMPT_COUNT =
        MAX_OFFLOAD_ATTEMPTS;
    localparam logic [ATTEMPT_STORAGE_WIDTH-1:0] FIRST_ATTEMPT_COUNT = 1;
    localparam logic [LEVEL_STORAGE_WIDTH-1:0] ASSERT_LEVEL = ASSERT_THRESHOLD;
    localparam logic [LEVEL_STORAGE_WIDTH-1:0] RECOVERY_LEVEL = RECOVERY_THRESHOLD;

    localparam logic [1:0] ST_IDLE = 2'd0;
    localparam logic [1:0] ST_WAIT = 2'd1;
    localparam logic [1:0] ST_COMMIT = 2'd2;
    localparam logic [1:0] ST_FAIL = 2'd3;

    logic [1:0] state;
    logic [ASSERT_COUNT_WIDTH-1:0] congestion_count;
    logic [RECOVERY_COUNT_WIDTH-1:0] recovery_count;
    logic [TIMEOUT_COUNT_WIDTH-1:0] timeout_count;
    logic [ATTEMPT_STORAGE_WIDTH-1:0] attempt_count;
    logic tracked_candidate_valid;
    logic [ID_STORAGE_WIDTH-1:0] tracked_candidate_id;
    logic [PACKET_STORAGE_WIDTH-1:0] packet_snapshot;
    logic identity_has_budget;

    assign identity_has_budget = tracked_candidate_valid
        && (candidate_id == tracked_candidate_id)
        && (attempt_count < MAX_ATTEMPT_COUNT);

    assign transfer_request_valid = (state == ST_WAIT);
    assign transfer_request_packet =
        (state == ST_WAIT) ? packet_snapshot : candidate_packet;
    assign sender_commit = (state == ST_COMMIT);
    assign transfer_failed = (state == ST_FAIL);


    always_comb begin
        offload_available = (state == ST_IDLE)
            && congestion_active
            && candidate_valid
            && candidate_eligible
            && candidate_route_legal
            && downstream_capacity_ok
            && (!tracked_candidate_valid
                || (candidate_id != tracked_candidate_id)
                || identity_has_budget);
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            congestion_active <= 1'b0;
            congestion_count <= '0;
            recovery_count <= '0;
        end else if (!congestion_active) begin
            recovery_count <= '0;
            if (congestion_level >= ASSERT_LEVEL) begin
                if (CONGESTION_PERSIST_CYCLES == 1
                    || congestion_count >= ASSERT_COUNT_LIMIT) begin
                    congestion_active <= 1'b1;
                    congestion_count <= '0;
                end else begin
                    congestion_count <= congestion_count + 1'b1;
                end
            end else begin
                congestion_count <= '0;
            end
        end else begin
            congestion_count <= '0;
            if (congestion_level <= RECOVERY_LEVEL) begin
                if (RECOVERY_PERSIST_CYCLES == 1
                    || recovery_count >= RECOVERY_COUNT_LIMIT) begin
                    congestion_active <= 1'b0;
                    recovery_count <= '0;
                end else begin
                    recovery_count <= recovery_count + 1'b1;
                end
            end else begin
                recovery_count <= '0;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            timeout_count <= '0;
            attempt_count <= '0;
            tracked_candidate_valid <= 1'b0;
            tracked_candidate_id <= '0;
            packet_snapshot <= '0;
        end else begin
            case (state)
                ST_IDLE: begin
                    timeout_count <= '0;
                    if (!candidate_valid) begin
                        tracked_candidate_valid <= 1'b0;
                        attempt_count <= '0;
                    end

                    if (offload_available) begin
                        packet_snapshot <= candidate_packet;
                        if (tracked_candidate_valid
                            && candidate_id == tracked_candidate_id) begin
                            if (attempt_count < MAX_ATTEMPT_COUNT)
                                attempt_count <= attempt_count + 1'b1;
                        end else begin
                            tracked_candidate_valid <= 1'b1;
                            tracked_candidate_id <= candidate_id;
                            attempt_count <= FIRST_ATTEMPT_COUNT;
                        end
                        state <= ST_WAIT;
                    end
                end

                ST_WAIT: begin
                    if (cancel || receiver_reject) begin
                        state <= ST_FAIL;
                    end else if (receiver_accept) begin
                        state <= ST_COMMIT;
                    end else if (timeout_count >= TIMEOUT_COUNT_LIMIT) begin
                        state <= ST_FAIL;
                    end else begin
                        timeout_count <= timeout_count + 1'b1;
                    end
                end

                ST_COMMIT: begin
                    state <= ST_IDLE;
                    timeout_count <= '0;
                    attempt_count <= MAX_ATTEMPT_COUNT;
                end

                ST_FAIL: begin
                    state <= ST_IDLE;
                    timeout_count <= '0;
                end

                default: begin
                    state <= ST_IDLE;
                    timeout_count <= '0;
                end
            endcase

        end
    end

    initial begin
        if (PACKET_WIDTH < 1)
            $fatal(1, "PACKET_WIDTH must be at least one");
        if (CANDIDATE_ID_WIDTH < 1)
            $fatal(1, "CANDIDATE_ID_WIDTH must be at least one");
        if (LEVEL_WIDTH < 1)
            $fatal(1, "LEVEL_WIDTH must be at least one");
        if (ASSERT_THRESHOLD < 0 || RECOVERY_THRESHOLD < 0)
            $fatal(1, "Congestion thresholds must be non-negative");
        if (ASSERT_THRESHOLD <= RECOVERY_THRESHOLD)
            $fatal(1, "ASSERT_THRESHOLD must be greater than RECOVERY_THRESHOLD");
        if (LEVEL_WIDTH < 32
            && ((64'(ASSERT_THRESHOLD) >= (64'd1 << LEVEL_WIDTH))
                || (64'(RECOVERY_THRESHOLD) >= (64'd1 << LEVEL_WIDTH))))
            $fatal(1, "Congestion thresholds must fit LEVEL_WIDTH");
        if (CONGESTION_PERSIST_CYCLES < 1 || RECOVERY_PERSIST_CYCLES < 1)
            $fatal(1, "Congestion and recovery persistence must be at least one cycle");
        if (TRANSFER_TIMEOUT_CYCLES < 1)
            $fatal(1, "TRANSFER_TIMEOUT_CYCLES must be at least one");
        if (MAX_OFFLOAD_ATTEMPTS < 1)
            $fatal(1, "MAX_OFFLOAD_ATTEMPTS must be at least one");
        if (ATTEMPT_COUNT_WIDTH < REQUIRED_ATTEMPT_WIDTH)
            $fatal(1, "ATTEMPT_COUNT_WIDTH cannot represent MAX_OFFLOAD_ATTEMPTS");
    end

endmodule
