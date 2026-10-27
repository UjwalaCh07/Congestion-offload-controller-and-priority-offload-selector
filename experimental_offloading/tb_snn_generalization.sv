`timescale 1ns/1ps

module tb_snn_generalization;
    localparam integer DIRECTIONS = snn_traffic_traces::DIRECTIONS;
    localparam integer TRACE_COUNT = snn_traffic_traces::TRACE_COUNT;
    localparam integer TRACE_LENGTH = snn_traffic_traces::TRACE_LENGTH;
    localparam integer HORIZON = snn_traffic_traces::HORIZON;
    localparam integer SCORED_WINDOWS = TRACE_LENGTH - HORIZON;
    localparam integer FAMILIES = 8;
    localparam integer METHODS = 3;
    localparam integer SETS = 2;
    localparam integer METHOD_RULE = 0;
    localparam integer METHOD_DEFAULT = 1;
    localparam integer METHOD_CONFIG19 = 2;
    localparam integer TREND_FALLING = 0;
    localparam integer TREND_STABLE = 1;
    localparam integer TREND_RISING = 2;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic [DIRECTIONS-1:0] feature_valid = '0;
    logic [DIRECTIONS-1:0][3:0] occupancy = '0;
    logic [DIRECTIONS-1:0][1:0] occupancy_trend = '0;
    logic [DIRECTIONS-1:0][3:0] traffic_count = '0;
    logic [DIRECTIONS-1:0] recent_congestion = '0;
    logic [DIRECTIONS-1:0] default_valid;
    logic [DIRECTIONS-1:0] default_prediction;
    logic [DIRECTIONS-1:0][7:0] default_activity;
    logic [DIRECTIONS-1:0] config19_valid;
    logic [DIRECTIONS-1:0] config19_prediction;
    logic [DIRECTIONS-1:0][7:0] config19_activity;

    integer occupancy_trace [0:TRACE_COUNT-1][0:DIRECTIONS-1][0:TRACE_LENGTH-1];
    integer traffic_trace [0:TRACE_COUNT-1][0:DIRECTIONS-1][0:TRACE_LENGTH-1];
    integer tp [0:METHODS-1][0:SETS-1];
    integer fp [0:METHODS-1][0:SETS-1];
    integer tn [0:METHODS-1][0:SETS-1];
    integer fn [0:METHODS-1][0:SETS-1];
    integer family_tp [0:METHODS-1][0:FAMILIES-1];
    integer family_fp [0:METHODS-1][0:FAMILIES-1];
    integer family_tn [0:METHODS-1][0:FAMILIES-1];
    integer family_fn [0:METHODS-1][0:FAMILIES-1];
    integer trace_tp [0:METHODS-1];
    integer trace_fp [0:METHODS-1];
    integer trace_tn [0:METHODS-1];
    integer trace_fn [0:METHODS-1];
    integer trace_early_sum [0:METHODS-1];
    integer trace_early_count [0:METHODS-1];
    integer trace_early_eligible [0:METHODS-1];
    integer trace_delay_sum [0:METHODS-1];
    integer trace_delay_count [0:METHODS-1];
    integer trace_delay_eligible [0:METHODS-1];
    integer early_sum [0:METHODS-1][0:SETS-1];
    integer early_count [0:METHODS-1][0:SETS-1];
    integer early_eligible [0:METHODS-1][0:SETS-1];
    integer delay_sum [0:METHODS-1][0:SETS-1];
    integer delay_count [0:METHODS-1][0:SETS-1];
    integer delay_eligible [0:METHODS-1][0:SETS-1];
    integer positive_labels [0:SETS-1];
    integer negative_labels [0:SETS-1];
    integer direction_window_count [0:SETS-1];
    integer crossing_by_direction [0:DIRECTIONS-1];
    integer early_prediction [0:METHODS-1][0:DIRECTIONS-1];
    integer detection_prediction [0:METHODS-1][0:DIRECTIONS-1];
    integer checks = 0;

    always #5 clk = ~clk;

    snn_congestion_predictor #(
        .NUM_DIRECTIONS(DIRECTIONS)
    ) default_snn (
        .clk,
        .rst_n,
        .feature_valid,
        .occupancy,
        .occupancy_trend,
        .traffic_count,
        .recent_congestion,
        .prediction_valid(default_valid),
        .predicted_congestion(default_prediction),
        .prediction_activity(default_activity)
    );

    snn_congestion_predictor #(
        .NUM_DIRECTIONS(DIRECTIONS),
        .LEAK_PER_OBSERVATION(0)
    ) config19_snn (
        .clk,
        .rst_n,
        .feature_valid,
        .occupancy,
        .occupancy_trend,
        .traffic_count,
        .recent_congestion,
        .prediction_valid(config19_valid),
        .predicted_congestion(config19_prediction),
        .prediction_activity(config19_activity)
    );

    function automatic logic baseline_prediction(
        input integer trace_id,
        input integer direction,
        input integer index
    );
        integer occ;
        integer traffic;
        logic rising;
        begin
            occ = occupancy_trace[trace_id][direction][index];
            traffic = traffic_trace[trace_id][direction][index];
            rising = occupancy_trace[trace_id][direction][index]
                > ((index == 0) ? 0
                    : occupancy_trace[trace_id][direction][index - 1]);
            baseline_prediction =
                (occ >= 10) || ((occ >= 6) && rising)
                || ((traffic >= 6) && rising);
        end
    endfunction

    function automatic string method_name(input integer method_id);
        case (method_id)
            METHOD_RULE: method_name = "RULE";
            METHOD_DEFAULT: method_name = "SNN_DEFAULT";
            METHOD_CONFIG19: method_name = "SNN_CONFIG19";
            default: method_name = "INVALID";
        endcase
    endfunction

    function automatic string family_name(input integer family_id);
        case (family_id)
            0: family_name = "RAMP";
            1: family_name = "SHORT_BURST";
            2: family_name = "SUSTAINED";
            3: family_name = "RECOVERY";
            4: family_name = "REPEATED_BURSTS";
            5: family_name = "STABLE_HIGH_TRAFFIC";
            6: family_name = "DIRECTIONAL_ASYMMETRY";
            7: family_name = "STAGGERED_ONSET";
            default: family_name = "INVALID";
        endcase
    endfunction

    function automatic integer metric_set(input integer trace_id);
        metric_set = (trace_id < snn_traffic_traces::TUNING_TRACE_COUNT)
            ? 0 : 1;
    endfunction

    task automatic check(input logic condition, input string message);
        begin
            checks++;
            if (condition !== 1'b1) begin
                $error("CHECK FAILED: %s at %0t", message, $time);
                $fatal(1);
            end
        end
    endtask

    task automatic reset_predictors;
        begin
            @(negedge clk);
            rst_n = 1'b0;
            feature_valid = '0;
            #1;
            check(default_valid == '0 && default_prediction == '0
                  && default_activity == '0,
                  "reset clears default SNN state");
            check(config19_valid == '0 && config19_prediction == '0
                  && config19_activity == '0,
                  "reset clears config 19 SNN state");
            @(posedge clk);
            #1;
            @(negedge clk);
            rst_n = 1'b1;
        end
    endtask

    task automatic print_set_metrics(
        input integer method_id,
        input integer set_id,
        input string set_name
    );
        integer predicted_positive;
        integer actual_positive;
        integer actual_negative;
        real precision_value;
        real recall_value;
        real fpr_value;
        begin
            predicted_positive = tp[method_id][set_id] + fp[method_id][set_id];
            actual_positive = tp[method_id][set_id] + fn[method_id][set_id];
            actual_negative = fp[method_id][set_id] + tn[method_id][set_id];
            $display("AGGREGATE set=%s method=%s direction_windows=%0d TP=%0d FP=%0d TN=%0d FN=%0d",
                set_name, method_name(method_id), direction_window_count[set_id],
                tp[method_id][set_id], fp[method_id][set_id],
                tn[method_id][set_id], fn[method_id][set_id]);
            if (predicted_positive == 0)
                $display("  precision=N/A (0 predicted positives)");
            else begin
                precision_value = 100.0 * tp[method_id][set_id]
                    / predicted_positive;
                $display("  precision=%0.2f%%", precision_value);
            end
            if (actual_positive == 0)
                $display("  recall=N/A (0 positive labels)");
            else begin
                recall_value = 100.0 * tp[method_id][set_id] / actual_positive;
                $display("  recall=%0.2f%%", recall_value);
            end
            if (actual_negative == 0)
                $display("  false_positive_rate=N/A (0 negative labels)");
            else begin
                fpr_value = 100.0 * fp[method_id][set_id] / actual_negative;
                $display("  false_positive_rate=%0.2f%%", fpr_value);
            end
            if (early_count[method_id][set_id] == 0)
                $display("  early_warning=N/A (0 warnings; eligible=%0d)",
                    early_eligible[method_id][set_id]);
            else
                $display("  early_warning=%0d/%0d eligible average=%0.2f windows",
                    early_count[method_id][set_id],
                    early_eligible[method_id][set_id],
                    1.0 * early_sum[method_id][set_id]
                        / early_count[method_id][set_id]);
            if (delay_count[method_id][set_id] == 0)
                $display("  detection_delay=N/A (0 detections; eligible=%0d)",
                    delay_eligible[method_id][set_id]);
            else
                $display("  detection_delay=%0d/%0d eligible average=%0.2f windows",
                    delay_count[method_id][set_id],
                    delay_eligible[method_id][set_id],
                    1.0 * delay_sum[method_id][set_id]
                        / delay_count[method_id][set_id]);
        end
    endtask

    initial begin : p_evaluate
        integer family;
        integer set_id;
        integer crossing;
        integer prediction;
        integer expected_early_pairs;
        integer expected_delay_pairs;
        integer methods_prediction [0:METHODS-1];
        integer unique_families_tuning [0:5];
        integer unique_families_heldout [0:1];
        logic label_value;

        for (integer method_id = 0; method_id < METHODS; method_id++) begin
            for (integer group_id = 0; group_id < SETS; group_id++) begin
                tp[method_id][group_id] = 0;
                fp[method_id][group_id] = 0;
                tn[method_id][group_id] = 0;
                fn[method_id][group_id] = 0;
                early_sum[method_id][group_id] = 0;
                early_count[method_id][group_id] = 0;
                early_eligible[method_id][group_id] = 0;
                delay_sum[method_id][group_id] = 0;
                delay_count[method_id][group_id] = 0;
                delay_eligible[method_id][group_id] = 0;
            end
            for (integer family_id = 0; family_id < FAMILIES; family_id++) begin
                family_tp[method_id][family_id] = 0;
                family_fp[method_id][family_id] = 0;
                family_tn[method_id][family_id] = 0;
                family_fn[method_id][family_id] = 0;
            end
        end
        positive_labels[0] = 0;
        positive_labels[1] = 0;
        negative_labels[0] = 0;
        negative_labels[1] = 0;
        direction_window_count[0] = 0;
        direction_window_count[1] = 0;
        for (integer family_id = 0; family_id < 6; family_id++)
            unique_families_tuning[family_id] = 0;
        for (integer family_id = 0; family_id < 2; family_id++)
            unique_families_heldout[family_id] = 0;

        for (integer trace_id = 0; trace_id < TRACE_COUNT; trace_id++) begin
            family = snn_traffic_traces::trace_family(trace_id);
            set_id = metric_set(trace_id);
            check((set_id == 0 && family < 6)
                  || (set_id == 1 && family >= 6),
                  "complete traffic families do not cross the tuning/held-out split");
            if (set_id == 0)
                unique_families_tuning[family]++;
            else
                unique_families_heldout[family - 6]++;
            for (integer direction = 0; direction < DIRECTIONS; direction++) begin
                for (integer index = 0; index < TRACE_LENGTH; index++) begin
                    occupancy_trace[trace_id][direction][index] =
                        snn_traffic_traces::trace_occupancy(
                            trace_id, direction, index);
                    traffic_trace[trace_id][direction][index] =
                        snn_traffic_traces::trace_traffic(
                            trace_id, direction, index);
                    check(occupancy_trace[trace_id][direction][index] >= 0
                          && occupancy_trace[trace_id][direction][index] <= 15,
                          "generated occupancy fits the four-bit interface");
                    check(traffic_trace[trace_id][direction][index] >= 0
                          && traffic_trace[trace_id][direction][index] <= 15,
                          "generated traffic count fits the four-bit interface");
                    check(occupancy_trace[trace_id][direction][index]
                          == snn_traffic_traces::trace_occupancy(
                              trace_id, direction, index)
                          && traffic_trace[trace_id][direction][index]
                          == snn_traffic_traces::trace_traffic(
                              trace_id, direction, index),
                          "fixed trace configuration reproduces identical samples");
                end
            end
        end
        for (integer family_id = 0; family_id < 6; family_id++)
            check(unique_families_tuning[family_id] == 4,
                  "each tuning family has four complete deterministic variants");
        for (integer family_id = 0; family_id < 2; family_id++)
            check(unique_families_heldout[family_id] == 4,
                  "each held-out family has four complete deterministic variants");

        reset_predictors();
        for (integer trace_id = 0; trace_id < TRACE_COUNT; trace_id++) begin
            family = snn_traffic_traces::trace_family(trace_id);
            set_id = metric_set(trace_id);
            for (integer method_id = 0; method_id < METHODS; method_id++) begin
                trace_tp[method_id] = 0;
                trace_fp[method_id] = 0;
                trace_tn[method_id] = 0;
                trace_fn[method_id] = 0;
                trace_early_sum[method_id] = 0;
                trace_early_count[method_id] = 0;
                trace_early_eligible[method_id] = 0;
                trace_delay_sum[method_id] = 0;
                trace_delay_count[method_id] = 0;
                trace_delay_eligible[method_id] = 0;
            end
            expected_early_pairs = 0;
            expected_delay_pairs = 0;
            for (integer direction = 0; direction < DIRECTIONS; direction++) begin
                crossing_by_direction[direction] =
                    snn_traffic_traces::first_crossing(trace_id, direction);
                if (crossing_by_direction[direction] > 0
                    && crossing_by_direction[direction] < TRACE_LENGTH)
                    expected_early_pairs++;
                if (crossing_by_direction[direction] < SCORED_WINDOWS)
                    expected_delay_pairs++;
                for (integer method_id = 0; method_id < METHODS; method_id++) begin
                    early_prediction[method_id][direction] = -1;
                    detection_prediction[method_id][direction] = -1;
                end
            end

            for (integer index = 0; index < SCORED_WINDOWS; index++) begin
                @(negedge clk);
                feature_valid = '1;
                for (integer direction = 0; direction < DIRECTIONS; direction++) begin
                    occupancy[direction] = occupancy_trace[trace_id][direction][index];
                    traffic_count[direction] = traffic_trace[trace_id][direction][index];
                    recent_congestion[direction] =
                        snn_traffic_traces::trace_history(trace_id, direction, index);
                    if (snn_traffic_traces::trace_is_rising(
                        trace_id, direction, index))
                        occupancy_trend[direction] = TREND_RISING;
                    else if (occupancy_trace[trace_id][direction][index]
                        < ((index == 0) ? 0
                            : occupancy_trace[trace_id][direction][index - 1]))
                        occupancy_trend[direction] = TREND_FALLING;
                    else
                        occupancy_trend[direction] = TREND_STABLE;
                end

                @(posedge clk);
                #1;
                check(default_valid == '1 && config19_valid == '1,
                      "both SNN variants update on the same observation window");
                for (integer direction = 0; direction < DIRECTIONS; direction++) begin
                    label_value = snn_traffic_traces::future_event(
                        trace_id, direction, index);
                    if (index + HORIZON < TRACE_LENGTH)
                        check(1'b1, "future-label lookahead stays inside the trace");
                    else
                        check(1'b0, "scored sample has a complete label horizon");
                    if (label_value)
                        positive_labels[set_id]++;
                    else
                        negative_labels[set_id]++;
                    direction_window_count[set_id]++;

                    methods_prediction[METHOD_RULE] =
                        baseline_prediction(trace_id, direction, index);
                    methods_prediction[METHOD_DEFAULT] =
                        default_prediction[direction];
                    methods_prediction[METHOD_CONFIG19] =
                        config19_prediction[direction];

                    for (integer method_id = 0; method_id < METHODS; method_id++) begin
                        prediction = methods_prediction[method_id];
                        if (label_value) begin
                            if (prediction) begin
                                tp[method_id][set_id]++;
                                trace_tp[method_id]++;
                                family_tp[method_id][family]++;
                            end else begin
                                fn[method_id][set_id]++;
                                trace_fn[method_id]++;
                                family_fn[method_id][family]++;
                            end
                        end else begin
                            if (prediction) begin
                                fp[method_id][set_id]++;
                                trace_fp[method_id]++;
                                family_fp[method_id][family]++;
                            end else begin
                                tn[method_id][set_id]++;
                                trace_tn[method_id]++;
                                family_tn[method_id][family]++;
                            end
                        end

                        crossing = crossing_by_direction[direction];
                        if (crossing > 0 && crossing < TRACE_LENGTH)
                            trace_early_eligible[method_id]++;
                        if (label_value && prediction && index < crossing
                            && early_prediction[method_id][direction] < 0)
                            early_prediction[method_id][direction] = index;
                        if (crossing < SCORED_WINDOWS)
                            trace_delay_eligible[method_id]++;
                        if (crossing < SCORED_WINDOWS && index >= crossing
                            && prediction
                            && detection_prediction[method_id][direction] < 0)
                            detection_prediction[method_id][direction] = index;
                    end
                end
            end

            for (integer direction = 0; direction < DIRECTIONS; direction++) begin
                crossing = crossing_by_direction[direction];
                for (integer method_id = 0; method_id < METHODS; method_id++) begin
                    if (crossing > 0 && crossing < TRACE_LENGTH
                        && early_prediction[method_id][direction] >= 0) begin
                        trace_early_sum[method_id] += crossing
                            - early_prediction[method_id][direction];
                        trace_early_count[method_id]++;
                    end
                    if (crossing < SCORED_WINDOWS
                        && detection_prediction[method_id][direction] >= 0) begin
                        trace_delay_sum[method_id] += detection_prediction[method_id][direction]
                            - crossing;
                        trace_delay_count[method_id]++;
                    end
                end
            end

            for (integer method_id = 0; method_id < METHODS; method_id++) begin
                check(trace_early_eligible[method_id] % SCORED_WINDOWS == 0
                      && trace_early_eligible[method_id] / SCORED_WINDOWS
                          == expected_early_pairs,
                      "early-warning eligibility counts complete-trace crossings exactly once");
                check(trace_delay_eligible[method_id] % SCORED_WINDOWS == 0
                      && trace_delay_eligible[method_id] / SCORED_WINDOWS
                          == expected_delay_pairs,
                      "detection eligibility counts scored crossings exactly once");
                early_sum[method_id][set_id] += trace_early_sum[method_id];
                early_count[method_id][set_id] += trace_early_count[method_id];
                early_eligible[method_id][set_id] += trace_early_eligible[method_id]
                    / SCORED_WINDOWS;
                delay_sum[method_id][set_id] += trace_delay_sum[method_id];
                delay_count[method_id][set_id] += trace_delay_count[method_id];
                delay_eligible[method_id][set_id] += trace_delay_eligible[method_id]
                    / SCORED_WINDOWS;
                $display("TRACE trace=%0d family=%s partition=%s method=%s TP=%0d FP=%0d TN=%0d FN=%0d",
                    trace_id, family_name(family),
                    (set_id == 0) ? "TUNING" : "HELDOUT",
                    method_name(method_id), trace_tp[method_id],
                    trace_fp[method_id], trace_tn[method_id], trace_fn[method_id]);
            end

            for (integer method_id = 0; method_id < METHODS; method_id++) begin
                if (trace_early_count[method_id] == 0)
                    $display("  TRACE_TIMING method=%s early=N/A eligible=%0d",
                        method_name(method_id), trace_early_eligible[method_id]
                            / SCORED_WINDOWS);
                else
                    $display("  TRACE_TIMING method=%s early=%0d/%0d average=%0.2f windows",
                        method_name(method_id), trace_early_count[method_id],
                        trace_early_eligible[method_id] / SCORED_WINDOWS,
                        1.0 * trace_early_sum[method_id]
                            / trace_early_count[method_id]);
                if (trace_delay_count[method_id] == 0)
                    $display("  TRACE_TIMING method=%s detection=N/A eligible=%0d",
                        method_name(method_id), trace_delay_eligible[method_id]
                            / SCORED_WINDOWS);
                else
                    $display("  TRACE_TIMING method=%s detection=%0d/%0d average=%0.2f windows",
                        method_name(method_id), trace_delay_count[method_id],
                        trace_delay_eligible[method_id] / SCORED_WINDOWS,
                        1.0 * trace_delay_sum[method_id]
                            / trace_delay_count[method_id]);
            end
            reset_predictors();
        end

        for (integer method_id = 0; method_id < METHODS; method_id++) begin
            for (integer set_index = 0; set_index < SETS; set_index++) begin
                check(tp[method_id][set_index] + fp[method_id][set_index]
                      + tn[method_id][set_index] + fn[method_id][set_index]
                      == direction_window_count[set_index],
                      "each method accounts for every shared labeled direction-window");
                check(tp[method_id][set_index] + fn[method_id][set_index]
                      == positive_labels[set_index]
                      && fp[method_id][set_index] + tn[method_id][set_index]
                      == negative_labels[set_index],
                      "all methods use identical ground-truth labels");
                check(early_count[method_id][set_index]
                      <= early_eligible[method_id][set_index]
                      && delay_count[method_id][set_index]
                      <= delay_eligible[method_id][set_index],
                      "timing measurements do not exceed eligible pair counts");
            end
            for (integer family_id = 0; family_id < FAMILIES; family_id++) begin
                check(family_tp[method_id][family_id]
                      + family_fp[method_id][family_id]
                      + family_tn[method_id][family_id]
                      + family_fn[method_id][family_id]
                      == 4 * DIRECTIONS * SCORED_WINDOWS,
                      "each traffic family has four complete trace variants");
            end
        end

        $display("TRACE_SPLIT tuning_traces=24 families=0..5 heldout_traces=8 families=6..7");
        $display("TRACE_LENGTH=%0d SCORED_WINDOWS=%0d HORIZON=%0d EVENT_THRESHOLD=%0d",
            TRACE_LENGTH, SCORED_WINDOWS, HORIZON,
            snn_traffic_traces::OCCUPANCY_EVENT_THRESHOLD);
        for (integer method_id = 0; method_id < METHODS; method_id++) begin
            print_set_metrics(method_id, 0, "TUNING");
            print_set_metrics(method_id, 1, "HELDOUT");
        end
        for (integer family_id = 0; family_id < FAMILIES; family_id++) begin
            for (integer method_id = 0; method_id < METHODS; method_id++) begin
                $display("FAMILY family=%s method=%s TP=%0d FP=%0d TN=%0d FN=%0d",
                    family_name(family_id), method_name(method_id),
                    family_tp[method_id][family_id],
                    family_fp[method_id][family_id],
                    family_tn[method_id][family_id],
                    family_fn[method_id][family_id]);
            end
        end
        $display("PASS: %0d generalization checks completed", checks);
        $finish;
    end
endmodule
