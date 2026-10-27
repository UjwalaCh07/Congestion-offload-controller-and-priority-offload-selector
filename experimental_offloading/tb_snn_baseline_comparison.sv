`timescale 1ns/1ps

module tb_snn_baseline_comparison;
    localparam int DIRECTIONS = 2;
    localparam int SCENARIOS = 10;
    localparam int TRACE_LENGTH = 18;
    localparam int PREDICTION_HORIZON = 2;
    localparam int EVALUATED_SAMPLES = TRACE_LENGTH - PREDICTION_HORIZON;
    localparam int GROUND_TRUTH_THRESHOLD = 12;

    localparam int TREND_FALLING = 0;
    localparam int TREND_STABLE = 1;
    localparam int TREND_RISING = 2;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic [DIRECTIONS-1:0] feature_valid = '0;
    logic [DIRECTIONS-1:0][3:0] occupancy = '0;
    logic [DIRECTIONS-1:0][1:0] occupancy_trend = '0;
    logic [DIRECTIONS-1:0][3:0] traffic_count = '0;
    logic [DIRECTIONS-1:0] recent_congestion = '0;
    logic [DIRECTIONS-1:0] prediction_valid;
    logic [DIRECTIONS-1:0] predicted_congestion;
    logic [DIRECTIONS-1:0][7:0] prediction_activity;

    integer snn_tp = 0;
    integer snn_fp = 0;
    integer snn_tn = 0;
    integer snn_fn = 0;
    integer base_tp = 0;
    integer base_fp = 0;
    integer base_tn = 0;
    integer base_fn = 0;
    integer positive_labels = 0;
    integer negative_labels = 0;
    integer total_samples = 0;
    integer checks = 0;

    integer snn_lead_sum [0:DIRECTIONS-1];
    integer snn_lead_count [0:DIRECTIONS-1];
    integer base_lead_sum [0:DIRECTIONS-1];
    integer base_lead_count [0:DIRECTIONS-1];
    integer snn_delay_sum [0:DIRECTIONS-1];
    integer snn_delay_count [0:DIRECTIONS-1];
    integer base_delay_sum [0:DIRECTIONS-1];
    integer base_delay_count [0:DIRECTIONS-1];
    integer snn_first_index_sum [0:DIRECTIONS-1];
    integer snn_first_index_count [0:DIRECTIONS-1];
    integer base_first_index_sum [0:DIRECTIONS-1];
    integer base_first_index_count [0:DIRECTIONS-1];

    integer pair_crossing [0:SCENARIOS-1][0:DIRECTIONS-1];
    integer pair_snn_first_index [0:SCENARIOS-1][0:DIRECTIONS-1];
    integer pair_base_first_index [0:SCENARIOS-1][0:DIRECTIONS-1];
    integer pair_snn_early_index [0:SCENARIOS-1][0:DIRECTIONS-1];
    integer pair_base_early_index [0:SCENARIOS-1][0:DIRECTIONS-1];
    integer pair_snn_detection_index [0:SCENARIOS-1][0:DIRECTIONS-1];
    integer pair_base_detection_index [0:SCENARIOS-1][0:DIRECTIONS-1];
    integer pair_snn_lead_sum [0:SCENARIOS-1][0:DIRECTIONS-1];
    integer pair_snn_lead_count [0:SCENARIOS-1][0:DIRECTIONS-1];
    integer pair_base_lead_sum [0:SCENARIOS-1][0:DIRECTIONS-1];
    integer pair_base_lead_count [0:SCENARIOS-1][0:DIRECTIONS-1];
    integer pair_snn_delay_sum [0:SCENARIOS-1][0:DIRECTIONS-1];
    integer pair_snn_delay_count [0:SCENARIOS-1][0:DIRECTIONS-1];
    integer pair_base_delay_sum [0:SCENARIOS-1][0:DIRECTIONS-1];
    integer pair_base_delay_count [0:SCENARIOS-1][0:DIRECTIONS-1];

    always #5 clk = ~clk;

    snn_congestion_predictor #(
        .NUM_DIRECTIONS(DIRECTIONS)
    ) dut (
        .clk,
        .rst_n,
        .feature_valid,
        .occupancy,
        .occupancy_trend,
        .traffic_count,
        .recent_congestion,
        .prediction_valid,
        .predicted_congestion,
        .prediction_activity
    );

    function automatic integer trace_occupancy(
        input integer scenario,
        input integer direction,
        input integer index
    );
        begin
            case (scenario)
                0: trace_occupancy = (direction == 0)
                    ? ((index < 15) ? index : 15) : 1;
                1: trace_occupancy = (direction == 0)
                    ? ((index >= 5 && index <= 6) ? 15 : 1) : 1;
                2: trace_occupancy = (direction == 0)
                    ? ((index == 6) ? 15 : 1) : 1;
                3: trace_occupancy = (direction == 0)
                    ? ((index >= 4) ? 14 : 2) : 1;
                4: trace_occupancy = (direction == 0)
                    ? ((index < 6) ? 14 : ((14 - 2 * (index - 6) > 1)
                        ? 14 - 2 * (index - 6) : 1)) : 1;
                5: trace_occupancy = (direction == 1)
                    ? ((index < 15) ? index : 15) : 1;
                6: trace_occupancy = (direction == 0)
                    ? ((index >= 4) ? 13 : 2)
                    : ((index >= 9) ? 14 : 1);
                7: trace_occupancy = (direction == 0) ? 3 : 2;
                8: trace_occupancy = (direction == 0)
                    ? ((index < 14) ? 1 + index : 14) : 1;
                9: trace_occupancy = (direction == 0)
                    ? (((index >= 3 && index <= 4) || (index >= 10 && index <= 11))
                        ? 14 : 1) : 1;
                default: trace_occupancy = 1;
            endcase
        end
    endfunction

    function automatic integer trace_traffic(
        input integer scenario,
        input integer direction,
        input integer index
    );
        begin
            case (scenario)
                0: trace_traffic = (direction == 0 && index >= 2) ? 4 : 0;
                1: trace_traffic = (direction == 0 && index == 4) ? 8 : 0;
                2: trace_traffic = (direction == 0 && index == 5) ? 8 : 0;
                3: trace_traffic = (direction == 0) ? 5 : 0;
                4: trace_traffic = (direction == 0 && index < 6) ? 5 : 0;
                5: trace_traffic = (direction == 1 && index >= 1) ? 7 : 0;
                6: trace_traffic = (direction == 0 && index >= 3) ? 4
                    : ((direction == 1 && index >= 8) ? 6 : 0);
                7: trace_traffic = (direction == 0) ? 12 : 1;
                8: trace_traffic = (direction == 0) ? 1 : 0;
                9: trace_traffic = (direction == 0
                    && ((index == 2) || (index == 9))) ? 9 : 0;
                default: trace_traffic = 0;
            endcase
        end
    endfunction

    function automatic logic trace_history(
        input integer scenario,
        input integer direction,
        input integer index
    );
        integer previous_occupancy;
        begin
            previous_occupancy = (index == 0)
                ? 0 : trace_occupancy(scenario, direction, index - 1);
            trace_history = previous_occupancy >= 8;
        end
    endfunction

    function automatic logic trace_is_rising(
        input integer scenario,
        input integer direction,
        input integer index
    );
        integer previous_occupancy;
        begin
            previous_occupancy = (index == 0)
                ? 0 : trace_occupancy(scenario, direction, index - 1);
            trace_is_rising =
                trace_occupancy(scenario, direction, index) > previous_occupancy;
        end
    endfunction

    function automatic logic trace_is_falling(
        input integer scenario,
        input integer direction,
        input integer index
    );
        integer previous_occupancy;
        begin
            previous_occupancy = (index == 0)
                ? 0 : trace_occupancy(scenario, direction, index - 1);
            trace_is_falling =
                trace_occupancy(scenario, direction, index) < previous_occupancy;
        end
    endfunction

    function automatic logic future_event(
        input integer scenario,
        input integer direction,
        input integer index
    );
        logic event_seen;
        begin
            event_seen = 1'b0;
            for (int offset = 1; offset <= PREDICTION_HORIZON; offset++) begin
                if (trace_occupancy(scenario, direction, index + offset)
                    >= GROUND_TRUTH_THRESHOLD)
                    event_seen = 1'b1;
            end
            future_event = event_seen;
        end
    endfunction

    function automatic integer first_crossing(
        input integer scenario,
        input integer direction
    );
        integer crossing;
        begin
            crossing = TRACE_LENGTH;
            for (int index = 0; index < TRACE_LENGTH; index++) begin
                if (crossing == TRACE_LENGTH
                    && trace_occupancy(scenario, direction, index)
                        >= GROUND_TRUTH_THRESHOLD)
                    crossing = index;
            end
            first_crossing = crossing;
        end
    endfunction

    function automatic logic baseline_prediction(
        input integer scenario,
        input integer direction,
        input integer index
    );
        integer occ;
        integer traffic;
        logic rising;
        begin
            occ = trace_occupancy(scenario, direction, index);
            traffic = trace_traffic(scenario, direction, index);
            rising = trace_is_rising(scenario, direction, index);
            baseline_prediction =
                (occ >= 10) || ((occ >= 6) && rising)
                || ((traffic >= 6) && rising);
        end
    endfunction

    task automatic check(input logic condition, input string message);
        begin
            checks = checks + 1;
            if (condition !== 1'b1) begin
                $error("CHECK FAILED: %s at %0t", message, $time);
                $fatal(1);
            end
        end
    endtask

    task automatic reset_model;
        begin
            @(negedge clk);
            rst_n = 1'b0;
            feature_valid = '0;
            #1;
            check(predicted_congestion == '0 && prediction_activity == '0
                  && prediction_valid == '0,
                  "reset clears predictor between independent traces");
            @(posedge clk);
            #1;
            @(negedge clk);
            rst_n = 1'b1;
        end
    endtask

    initial begin : p_run_traces
        integer crossing;
        integer snn_first;
        integer base_first;
        integer snn_early;
        integer base_early;
        integer snn_detection;
        integer base_detection;
        integer aggregate_lead_sum [0:1];
        integer aggregate_lead_count [0:1];
        integer aggregate_delay_sum [0:1];
        integer aggregate_delay_count [0:1];
        integer aggregate_first_sum [0:1];
        integer aggregate_first_count [0:1];
        integer scenario_index;
        integer direction_index;
        integer crossing_pair_count;
        integer early_eligible_pair_count;
        integer aggregate_crossing_pair_count;
        integer aggregate_early_eligible_pair_count;
        logic truth;
        logic snn_prediction;
        logic base_prediction;
        real precision_value;
        real recall_value;
        real fpr_value;
        real first_index_average;

        for (int direction = 0; direction < DIRECTIONS; direction++) begin
            snn_lead_sum[direction] = 0;
            snn_lead_count[direction] = 0;
            base_lead_sum[direction] = 0;
            base_lead_count[direction] = 0;
            snn_delay_sum[direction] = 0;
            snn_delay_count[direction] = 0;
            base_delay_sum[direction] = 0;
            base_delay_count[direction] = 0;
            snn_first_index_sum[direction] = 0;
            snn_first_index_count[direction] = 0;
            base_first_index_sum[direction] = 0;
            base_first_index_count[direction] = 0;
        end
        aggregate_lead_sum[0] = 0;
        aggregate_lead_sum[1] = 0;
        aggregate_lead_count[0] = 0;
        aggregate_lead_count[1] = 0;
        aggregate_delay_sum[0] = 0;
        aggregate_delay_sum[1] = 0;
        aggregate_delay_count[0] = 0;
        aggregate_delay_count[1] = 0;
        aggregate_first_sum[0] = 0;
        aggregate_first_sum[1] = 0;
        aggregate_first_count[0] = 0;
        aggregate_first_count[1] = 0;
        reset_model();
        for (scenario_index = 0; scenario_index < SCENARIOS; scenario_index++) begin
            reset_model();
            for (direction_index = 0; direction_index < DIRECTIONS; direction_index++) begin
                pair_crossing[scenario_index][direction_index] =
                    first_crossing(scenario_index, direction_index);
                pair_snn_first_index[scenario_index][direction_index] = -1;
                pair_base_first_index[scenario_index][direction_index] = -1;
                pair_snn_early_index[scenario_index][direction_index] = -1;
                pair_base_early_index[scenario_index][direction_index] = -1;
                pair_snn_detection_index[scenario_index][direction_index] = -1;
                pair_base_detection_index[scenario_index][direction_index] = -1;
                pair_snn_lead_sum[scenario_index][direction_index] = 0;
                pair_snn_lead_count[scenario_index][direction_index] = 0;
                pair_base_lead_sum[scenario_index][direction_index] = 0;
                pair_base_lead_count[scenario_index][direction_index] = 0;
                pair_snn_delay_sum[scenario_index][direction_index] = 0;
                pair_snn_delay_count[scenario_index][direction_index] = 0;
                pair_base_delay_sum[scenario_index][direction_index] = 0;
                pair_base_delay_count[scenario_index][direction_index] = 0;
            end

            for (int index = 0; index < EVALUATED_SAMPLES; index++) begin
                @(negedge clk);
                feature_valid = '1;
                for (int direction = 0; direction < DIRECTIONS; direction++) begin
                    occupancy[direction] =
                        trace_occupancy(scenario_index, direction, index);
                    traffic_count[direction] =
                        trace_traffic(scenario_index, direction, index);
                    recent_congestion[direction] =
                        trace_history(scenario_index, direction, index);
                    if (trace_is_rising(scenario_index, direction, index))
                        occupancy_trend[direction] = TREND_RISING;
                    else if (trace_is_falling(scenario_index, direction, index))
                        occupancy_trend[direction] = TREND_FALLING;
                    else
                        occupancy_trend[direction] = TREND_STABLE;
                end

                @(posedge clk);
                #1;
                check(prediction_valid == '1,
                      "prediction valid for each scored observation window");
                total_samples++;

                for (int direction = 0; direction < DIRECTIONS; direction++) begin
                    truth = future_event(scenario_index, direction, index);
                    snn_prediction = predicted_congestion[direction];
                    base_prediction =
                        baseline_prediction(scenario_index, direction, index);
                    if (truth) begin
                        positive_labels++;
                        if (snn_prediction) snn_tp++;
                        else snn_fn++;
                        if (base_prediction) base_tp++;
                        else base_fn++;
                    end else begin
                        negative_labels++;
                        if (snn_prediction) snn_fp++;
                        else snn_tn++;
                        if (base_prediction) base_fp++;
                        else base_tn++;
                    end

                    if (snn_prediction
                        && pair_snn_first_index[scenario_index][direction] < 0)
                        pair_snn_first_index[scenario_index][direction] = index;
                    if (base_prediction
                        && pair_base_first_index[scenario_index][direction] < 0)
                        pair_base_first_index[scenario_index][direction] = index;

                    crossing = pair_crossing[scenario_index][direction];
                    if (crossing < TRACE_LENGTH && truth && index < crossing) begin
                        if (snn_prediction
                            && pair_snn_early_index[scenario_index][direction] < 0)
                            pair_snn_early_index[scenario_index][direction] = index;
                        if (base_prediction
                            && pair_base_early_index[scenario_index][direction] < 0)
                            pair_base_early_index[scenario_index][direction] = index;
                    end

                    if (crossing < EVALUATED_SAMPLES && index >= crossing) begin
                        if (snn_prediction
                            && pair_snn_detection_index[scenario_index][direction] < 0)
                            pair_snn_detection_index[scenario_index][direction] = index;
                        if (base_prediction
                            && pair_base_detection_index[scenario_index][direction] < 0)
                            pair_base_detection_index[scenario_index][direction] = index;
                    end
                end
            end

            for (direction_index = 0; direction_index < DIRECTIONS; direction_index++) begin
                crossing = pair_crossing[scenario_index][direction_index];
                snn_early = pair_snn_early_index[scenario_index][direction_index];
                base_early = pair_base_early_index[scenario_index][direction_index];
                snn_detection = pair_snn_detection_index[scenario_index][direction_index];
                base_detection = pair_base_detection_index[scenario_index][direction_index];

                if (crossing < TRACE_LENGTH) begin
                    if (snn_early >= 0) begin
                        pair_snn_lead_sum[scenario_index][direction_index] =
                            crossing - snn_early;
                        pair_snn_lead_count[scenario_index][direction_index] = 1;
                        aggregate_lead_sum[0] += crossing - snn_early;
                        aggregate_lead_count[0]++;
                        snn_lead_sum[direction_index] += crossing - snn_early;
                        snn_lead_count[direction_index]++;
                    end
                    if (base_early >= 0) begin
                        pair_base_lead_sum[scenario_index][direction_index] =
                            crossing - base_early;
                        pair_base_lead_count[scenario_index][direction_index] = 1;
                        aggregate_lead_sum[1] += crossing - base_early;
                        aggregate_lead_count[1]++;
                        base_lead_sum[direction_index] += crossing - base_early;
                        base_lead_count[direction_index]++;
                    end
                    if (snn_detection >= 0) begin
                        pair_snn_delay_sum[scenario_index][direction_index] =
                            snn_detection - crossing;
                        pair_snn_delay_count[scenario_index][direction_index] = 1;
                        aggregate_delay_sum[0] += snn_detection - crossing;
                        aggregate_delay_count[0]++;
                        snn_delay_sum[direction_index] += snn_detection - crossing;
                        snn_delay_count[direction_index]++;
                    end
                    if (base_detection >= 0) begin
                        pair_base_delay_sum[scenario_index][direction_index] =
                            base_detection - crossing;
                        pair_base_delay_count[scenario_index][direction_index] = 1;
                        aggregate_delay_sum[1] += base_detection - crossing;
                        aggregate_delay_count[1]++;
                        base_delay_sum[direction_index] += base_detection - crossing;
                        base_delay_count[direction_index]++;
                    end
                end

                if (pair_snn_first_index[scenario_index][direction_index] >= 0) begin
                    snn_first_index_sum[direction_index] +=
                        pair_snn_first_index[scenario_index][direction_index];
                    snn_first_index_count[direction_index]++;
                    aggregate_first_sum[0] +=
                        pair_snn_first_index[scenario_index][direction_index];
                    aggregate_first_count[0]++;
                end
                if (pair_base_first_index[scenario_index][direction_index] >= 0) begin
                    base_first_index_sum[direction_index] +=
                        pair_base_first_index[scenario_index][direction_index];
                    base_first_index_count[direction_index]++;
                    aggregate_first_sum[1] +=
                        pair_base_first_index[scenario_index][direction_index];
                    aggregate_first_count[1]++;
                end

                $display("PAIR scenario=%0d direction=%0d crossing=%0d SNN_first_assertion=%0d SNN_early_index=%0d lead=%0d SNN_detection_index=%0d delay=%0d BASELINE_first_assertion=%0d BASELINE_early_index=%0d lead=%0d BASELINE_detection_index=%0d delay=%0d",
                    scenario_index, direction_index,
                    (crossing == TRACE_LENGTH) ? -1 : crossing,
                    pair_snn_first_index[scenario_index][direction_index],
                    pair_snn_early_index[scenario_index][direction_index],
                    pair_snn_lead_sum[scenario_index][direction_index],
                    pair_snn_detection_index[scenario_index][direction_index],
                    pair_snn_delay_sum[scenario_index][direction_index],
                    pair_base_first_index[scenario_index][direction_index],
                    pair_base_early_index[scenario_index][direction_index],
                    pair_base_lead_sum[scenario_index][direction_index],
                    pair_base_detection_index[scenario_index][direction_index],
                    pair_base_delay_sum[scenario_index][direction_index]);

                check(pair_snn_lead_count[scenario_index][direction_index] <= 1
                      && pair_snn_delay_count[scenario_index][direction_index] <= 1
                      && pair_base_lead_count[scenario_index][direction_index] <= 1
                      && pair_base_delay_count[scenario_index][direction_index] <= 1,
                      "each scenario-direction pair contributes at most one timing value");
                check(pair_snn_first_index[scenario_index][direction_index] < EVALUATED_SAMPLES
                      && pair_base_first_index[scenario_index][direction_index] < EVALUATED_SAMPLES,
                      "first assertion indices remain inside the scored window");
                check(pair_snn_detection_index[scenario_index][direction_index] < EVALUATED_SAMPLES
                      && pair_base_detection_index[scenario_index][direction_index] < EVALUATED_SAMPLES,
                      "post-crossing detection indices remain inside the scored window");
                if (pair_snn_early_index[scenario_index][direction_index] >= 0)
                    check(pair_snn_early_index[scenario_index][direction_index] < crossing,
                          "SNN early warning precedes that direction's first crossing");
                if (pair_base_early_index[scenario_index][direction_index] >= 0)
                    check(pair_base_early_index[scenario_index][direction_index] < crossing,
                          "baseline early warning precedes that direction's first crossing");
            end
        end

        check(total_samples == SCENARIOS * EVALUATED_SAMPLES,
              "all scenarios use the same valid evaluation window count");
        check(positive_labels + negative_labels
              == total_samples * DIRECTIONS,
              "ground-truth label count matches all scored direction-windows");
        check(snn_tp + snn_fp + snn_tn + snn_fn
              == total_samples * DIRECTIONS,
              "each SNN direction-window contributes exactly once");
        check(base_tp + base_fp + base_tn + base_fn
              == total_samples * DIRECTIONS,
              "each baseline direction-window contributes exactly once");
        check(snn_tp + snn_fn == positive_labels
              && base_tp + base_fn == positive_labels,
              "both predictors use identical positive labels");
        check(snn_fp + snn_tn == negative_labels
              && base_fp + base_tn == negative_labels,
              "both predictors use identical negative labels");

        $display("SCENARIOS=%0d WINDOWS_PER_TRACE=%0d SCORED_WINDOWS=%0d SCORED_DIRECTION_WINDOWS=%0d",
                 SCENARIOS, EVALUATED_SAMPLES, total_samples,
                 total_samples * DIRECTIONS);
        $display("SNN TP=%0d FP=%0d TN=%0d FN=%0d",
                 snn_tp, snn_fp, snn_tn, snn_fn);
        $display("BASELINE TP=%0d FP=%0d TN=%0d FN=%0d",
                 base_tp, base_fp, base_tn, base_fn);
        if (snn_tp + snn_fp == 0) $display("SNN precision=N/A (no positive predictions)");
        else begin
            precision_value = 100.0 * snn_tp / (snn_tp + snn_fp);
            $display("SNN precision=%0.2f%%", precision_value);
        end
        if (snn_tp + snn_fn == 0) $display("SNN recall=N/A (no positive labels)");
        else begin
            recall_value = 100.0 * snn_tp / (snn_tp + snn_fn);
            $display("SNN recall=%0.2f%%", recall_value);
        end
        if (snn_fp + snn_tn == 0) $display("SNN false_positive_rate=N/A (no negative labels)");
        else begin
            fpr_value = 100.0 * snn_fp / (snn_fp + snn_tn);
            $display("SNN false_positive_rate=%0.2f%%", fpr_value);
        end
        if (base_tp + base_fp == 0) $display("BASELINE precision=N/A (no positive predictions)");
        else begin
            precision_value = 100.0 * base_tp / (base_tp + base_fp);
            $display("BASELINE precision=%0.2f%%", precision_value);
        end
        if (base_tp + base_fn == 0) $display("BASELINE recall=N/A (no positive labels)");
        else begin
            recall_value = 100.0 * base_tp / (base_tp + base_fn);
            $display("BASELINE recall=%0.2f%%", recall_value);
        end
        if (base_fp + base_tn == 0) $display("BASELINE false_positive_rate=N/A (no negative labels)");
        else begin
            fpr_value = 100.0 * base_fp / (base_fp + base_tn);
            $display("BASELINE false_positive_rate=%0.2f%%", fpr_value);
        end

        for (direction_index = 0; direction_index < DIRECTIONS; direction_index++) begin
            crossing_pair_count = 0;
            early_eligible_pair_count = 0;
            for (scenario_index = 0; scenario_index < SCENARIOS; scenario_index++) begin
                if (pair_crossing[scenario_index][direction_index] < EVALUATED_SAMPLES)
                    crossing_pair_count++;
                if (pair_crossing[scenario_index][direction_index] > 0
                    && pair_crossing[scenario_index][direction_index] < TRACE_LENGTH)
                    early_eligible_pair_count++;
            end
            check(snn_lead_count[direction_index] <= early_eligible_pair_count
                  && base_lead_count[direction_index] <= early_eligible_pair_count,
                  "early-warning counts do not exceed direction-eligible crossings");
            check(snn_delay_count[direction_index] <= crossing_pair_count
                  && base_delay_count[direction_index] <= crossing_pair_count,
                  "detection counts do not exceed scored direction crossings");
            if (snn_first_index_count[direction_index] > 0) begin
                first_index_average = 1.0 * snn_first_index_sum[direction_index]
                    / snn_first_index_count[direction_index];
                $display("DIRECTION=%0d SNN_first_assertion measured_pairs=%0d average_index=%0.2f",
                    direction_index, snn_first_index_count[direction_index],
                    first_index_average);
            end else $display("DIRECTION=%0d SNN_first_assertion N/A (0 asserted pairs)", direction_index);
            if (base_first_index_count[direction_index] > 0) begin
                first_index_average = 1.0 * base_first_index_sum[direction_index]
                    / base_first_index_count[direction_index];
                $display("DIRECTION=%0d BASELINE_first_assertion measured_pairs=%0d average_index=%0.2f",
                    direction_index, base_first_index_count[direction_index],
                    first_index_average);
            end else $display("DIRECTION=%0d BASELINE_first_assertion N/A (0 asserted pairs)", direction_index);
            if (snn_lead_count[direction_index] > 0) begin
                $display("DIRECTION=%0d SNN_early_lead measured_pairs=%0d eligible_pairs=%0d total=%0d average=%0.2f windows",
                    direction_index, snn_lead_count[direction_index],
                    early_eligible_pair_count,
                    snn_lead_sum[direction_index],
                    (snn_lead_count[direction_index] == 0) ? 0.0
                    : 1.0 * snn_lead_sum[direction_index] / snn_lead_count[direction_index]);
            end else $display("DIRECTION=%0d SNN_early_lead N/A (0 measured warnings; eligible_pairs=%0d)", direction_index, early_eligible_pair_count);
            if (snn_delay_count[direction_index] > 0)
                $display("DIRECTION=%0d SNN_detection_delay measured_pairs=%0d crossing_pairs=%0d total=%0d average=%0.2f windows",
                    direction_index, snn_delay_count[direction_index],
                    crossing_pair_count,
                    snn_delay_sum[direction_index],
                    1.0 * snn_delay_sum[direction_index] / snn_delay_count[direction_index]);
            else $display("DIRECTION=%0d SNN_detection_delay N/A (0 detections; crossing_pairs=%0d)", direction_index, crossing_pair_count);
            if (base_lead_count[direction_index] > 0)
                $display("DIRECTION=%0d BASELINE_early_lead measured_pairs=%0d eligible_pairs=%0d total=%0d average=%0.2f windows",
                    direction_index, base_lead_count[direction_index],
                    early_eligible_pair_count,
                    base_lead_sum[direction_index],
                    1.0 * base_lead_sum[direction_index] / base_lead_count[direction_index]);
            else $display("DIRECTION=%0d BASELINE_early_lead N/A (0 measured warnings; eligible_pairs=%0d)", direction_index, early_eligible_pair_count);
            if (base_delay_count[direction_index] > 0)
                $display("DIRECTION=%0d BASELINE_detection_delay measured_pairs=%0d crossing_pairs=%0d total=%0d average=%0.2f windows",
                    direction_index, base_delay_count[direction_index],
                    crossing_pair_count,
                    base_delay_sum[direction_index],
                    1.0 * base_delay_sum[direction_index] / base_delay_count[direction_index]);
            else $display("DIRECTION=%0d BASELINE_detection_delay N/A (0 detections; crossing_pairs=%0d)", direction_index, crossing_pair_count);
        end

        check(aggregate_lead_count[0] == snn_lead_count[0] + snn_lead_count[1],
              "SNN aggregate early-lead denominator equals per-direction totals");
        check(aggregate_lead_count[1] == base_lead_count[0] + base_lead_count[1],
              "baseline aggregate early-lead denominator equals per-direction totals");
        check(aggregate_delay_count[0] == snn_delay_count[0] + snn_delay_count[1],
              "SNN aggregate detection denominator equals per-direction totals");
        check(aggregate_delay_count[1] == base_delay_count[0] + base_delay_count[1],
              "baseline aggregate detection denominator equals per-direction totals");
        check(aggregate_first_count[0]
              == snn_first_index_count[0] + snn_first_index_count[1],
              "SNN aggregate first assertion denominator equals per-direction totals");
        check(aggregate_first_count[1]
              == base_first_index_count[0] + base_first_index_count[1],
              "baseline aggregate first assertion denominator equals per-direction totals");

        aggregate_crossing_pair_count = 0;
        aggregate_early_eligible_pair_count = 0;
        for (scenario_index = 0; scenario_index < SCENARIOS; scenario_index++) begin
            for (direction_index = 0; direction_index < DIRECTIONS; direction_index++) begin
                if (pair_crossing[scenario_index][direction_index] < EVALUATED_SAMPLES)
                    aggregate_crossing_pair_count++;
                if (pair_crossing[scenario_index][direction_index] > 0
                    && pair_crossing[scenario_index][direction_index] < TRACE_LENGTH)
                    aggregate_early_eligible_pair_count++;
            end
        end
        check(aggregate_lead_count[0] <= aggregate_early_eligible_pair_count
              && aggregate_lead_count[1] <= aggregate_early_eligible_pair_count,
              "aggregate early-warning counts do not exceed eligible crossings");
        check(aggregate_delay_count[0] <= aggregate_crossing_pair_count
              && aggregate_delay_count[1] <= aggregate_crossing_pair_count,
              "aggregate detection counts do not exceed scored crossings");

        for (int predictor = 0; predictor < 2; predictor++) begin
            if (aggregate_first_count[predictor] > 0)
                $display("AGGREGATE predictor=%0d first_assertion measured_pairs=%0d average_index=%0.2f",
                    predictor, aggregate_first_count[predictor],
                    1.0 * aggregate_first_sum[predictor]
                        / aggregate_first_count[predictor]);
            else $display("AGGREGATE predictor=%0d first_assertion N/A (0 asserted pairs)", predictor);
            if (aggregate_lead_count[predictor] > 0)
                $display("AGGREGATE predictor=%0d early_lead measured_pairs=%0d eligible_pairs=%0d total=%0d average=%0.2f windows",
                    predictor, aggregate_lead_count[predictor],
                    aggregate_early_eligible_pair_count,
                    aggregate_lead_sum[predictor],
                    1.0 * aggregate_lead_sum[predictor]
                        / aggregate_lead_count[predictor]);
            else $display("AGGREGATE predictor=%0d early_lead N/A (0 measured pairs)", predictor);
            if (aggregate_delay_count[predictor] > 0)
                $display("AGGREGATE predictor=%0d detection_delay measured_pairs=%0d crossing_pairs=%0d total=%0d average=%0.2f windows",
                    predictor, aggregate_delay_count[predictor],
                    aggregate_crossing_pair_count,
                    aggregate_delay_sum[predictor],
                    1.0 * aggregate_delay_sum[predictor]
                        / aggregate_delay_count[predictor]);
            else $display("AGGREGATE predictor=%0d detection_delay N/A (0 measured pairs)", predictor);
        end

        $display("Timing definitions: first assertion index within scored windows from trace index zero; detection delay only for predictions at/after a crossing in scored windows; early lead only for positive horizon labels strictly before crossing.");
        $display("PASS: %0d comparison checks completed", checks);
        $finish;
    end
endmodule
