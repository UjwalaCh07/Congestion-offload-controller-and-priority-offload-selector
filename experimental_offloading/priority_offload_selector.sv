`timescale 1ns/1ps

module priority_offload_selector #(
    parameter int NUM_CANDIDATES = 5,
    parameter int PRIORITY_WIDTH = 3,
    parameter int LEVEL_WIDTH = 8,
    parameter int AGE_LIMIT_CYCLES = 32,
    parameter bit HIGHER_VALUE_IS_HIGHER_PRIORITY = 1'b0,
    parameter int INDEX_WIDTH =
        (NUM_CANDIDATES > 1) ? $clog2(NUM_CANDIDATES) : 1
) (
    input  logic                                      clk,
    input  logic                                      rst_n,
    input  logic [((LEVEL_WIDTH > 0) ? LEVEL_WIDTH : 1)-1:0] congestion_level,
    input  logic [((LEVEL_WIDTH > 0) ? LEVEL_WIDTH : 1)-1:0] congestion_threshold,
    input  logic [((PRIORITY_WIDTH > 0) ? PRIORITY_WIDTH : 1)-1:0]
                                                     lowest_offload_priority,
    input  logic [((NUM_CANDIDATES > 0) ? NUM_CANDIDATES : 1)-1:0]
                                                     candidate_valid,
    input  logic [((NUM_CANDIDATES > 0) ? NUM_CANDIDATES : 1)-1:0]
                 [((PRIORITY_WIDTH > 0) ? PRIORITY_WIDTH : 1)-1:0]
                                                     candidate_priority,
    input  logic [((NUM_CANDIDATES > 0) ? NUM_CANDIDATES : 1)-1:0]
                                                     candidate_route_legal,
    input  logic [((NUM_CANDIDATES > 0) ? NUM_CANDIDATES : 1)-1:0]
                                                     candidate_capacity_ok,
    input  logic [((NUM_CANDIDATES > 0) ? NUM_CANDIDATES : 1)-1:0]
                                                     candidate_serviced,
    output logic                                      selected_valid,
    output logic [((INDEX_WIDTH > 0) ? INDEX_WIDTH : 1)-1:0]
                                                     selected_index,
    output logic [((NUM_CANDIDATES > 0) ? NUM_CANDIDATES : 1)-1:0]
                                                     selected_onehot
);

    localparam int CANDIDATE_STORAGE_COUNT =
        (NUM_CANDIDATES > 0) ? NUM_CANDIDATES : 1;
    localparam int INDEX_STORAGE_WIDTH = (INDEX_WIDTH > 0) ? INDEX_WIDTH : 1;
    localparam int AGE_COUNTER_WIDTH =
        (AGE_LIMIT_CYCLES > 1) ? $clog2(AGE_LIMIT_CYCLES + 1) : 1;
    localparam int REQUIRED_INDEX_WIDTH =
        (NUM_CANDIDATES > 1) ? $clog2(NUM_CANDIDATES) : 1;
    localparam logic [AGE_COUNTER_WIDTH-1:0] AGE_LIMIT_VALUE =
        AGE_LIMIT_CYCLES;

    logic [AGE_COUNTER_WIDTH-1:0] waiting_age [0:CANDIDATE_STORAGE_COUNT-1];
    logic [CANDIDATE_STORAGE_COUNT-1:0] eligible;
    logic [CANDIDATE_STORAGE_COUNT-1:0] aged;
    logic [INDEX_STORAGE_WIDTH-1:0] round_robin_start;
    logic serviced_vector_valid;
    integer serviced_count;
    integer serviced_index;
    integer round_robin_start_int;

    always_comb begin : p_service_decode
        serviced_count = 0;
        serviced_index = 0;
        for (int i = 0; i < NUM_CANDIDATES; i++) begin
            if (candidate_serviced[i]) begin
                serviced_count = serviced_count + 1;
                serviced_index = i;
            end
        end
        serviced_vector_valid = (serviced_count <= 1);
        round_robin_start_int = round_robin_start;
    end

    always_comb begin : p_select_candidate
        integer chosen;
        integer candidate_distance;
        integer best_distance;
        logic have_aged;
        logic [AGE_COUNTER_WIDTH-1:0] best_age;

        eligible = '0;
        aged = '0;
        selected_valid = 1'b0;
        selected_index = '0;
        selected_onehot = '0;
        chosen = -1;
        candidate_distance = 0;
        best_distance = 0;
        have_aged = 1'b0;
        best_age = '0;

        for (int i = 0; i < NUM_CANDIDATES; i++) begin
            if (i >= round_robin_start_int)
                candidate_distance = i - round_robin_start_int;
            else
                candidate_distance = NUM_CANDIDATES - round_robin_start_int + i;

            aged[i] = (waiting_age[i] == AGE_LIMIT_VALUE);
            if (candidate_valid[i]
                && candidate_route_legal[i]
                && candidate_capacity_ok[i]
                && (congestion_level >= congestion_threshold)) begin
                if (HIGHER_VALUE_IS_HIGHER_PRIORITY)
                    eligible[i] =
                        (candidate_priority[i] <= lowest_offload_priority) || aged[i];
                else
                    eligible[i] =
                        (candidate_priority[i] >= lowest_offload_priority) || aged[i];
            end

            if (eligible[i]) begin
                if (chosen == -1) begin
                    chosen = i;
                    have_aged = aged[i];
                    best_age = waiting_age[i];
                    best_distance = candidate_distance;
                end else if (aged[i] && !have_aged) begin
                    chosen = i;
                    have_aged = 1'b1;
                    best_age = waiting_age[i];
                    best_distance = candidate_distance;
                end else if (aged[i] == have_aged) begin
                    if (aged[i]) begin
                        if (waiting_age[i] > best_age
                            || (waiting_age[i] == best_age
                                && candidate_distance < best_distance)) begin
                            chosen = i;
                            best_age = waiting_age[i];
                            best_distance = candidate_distance;
                        end
                    end else if (HIGHER_VALUE_IS_HIGHER_PRIORITY) begin
                        if (candidate_priority[i] < candidate_priority[chosen]
                            || (candidate_priority[i] == candidate_priority[chosen]
                                && candidate_distance < best_distance)) begin
                            chosen = i;
                            best_distance = candidate_distance;
                        end
                    end else begin
                        if (candidate_priority[i] > candidate_priority[chosen]
                            || (candidate_priority[i] == candidate_priority[chosen]
                                && candidate_distance < best_distance)) begin
                            chosen = i;
                            best_distance = candidate_distance;
                        end
                    end
                end
            end
        end

        if (chosen >= 0) begin
            selected_valid = 1'b1;
            selected_index = chosen;
            selected_onehot[chosen] = 1'b1;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            round_robin_start <= '0;
            for (int i = 0; i < NUM_CANDIDATES; i++)
                waiting_age[i] <= '0;
        end else begin
            for (int i = 0; i < NUM_CANDIDATES; i++) begin
                if (!candidate_valid[i]
                    || !candidate_route_legal[i]
                    || !candidate_capacity_ok[i]
                    || congestion_level < congestion_threshold) begin
                    waiting_age[i] <= '0;
                end else if (serviced_vector_valid && candidate_serviced[i]) begin
                    waiting_age[i] <= '0;
                end else if (waiting_age[i] < AGE_LIMIT_VALUE) begin
                    waiting_age[i] <= waiting_age[i] + 1'b1;
                end
            end

            if (serviced_vector_valid && serviced_count == 1) begin
                if (serviced_index == NUM_CANDIDATES - 1)
                    round_robin_start <= '0;
                else
                    round_robin_start <= serviced_index + 1;
            end
        end
    end

    initial begin
        if (NUM_CANDIDATES < 1)
            $fatal(1, "NUM_CANDIDATES must be at least one");
        if (PRIORITY_WIDTH < 1 || LEVEL_WIDTH < 1)
            $fatal(1, "Priority and congestion widths must be at least one");
        if (AGE_LIMIT_CYCLES < 1)
            $fatal(1, "AGE_LIMIT_CYCLES must be at least one");
        if (INDEX_WIDTH < REQUIRED_INDEX_WIDTH)
            $fatal(1, "INDEX_WIDTH is too small for NUM_CANDIDATES");
    end

endmodule
