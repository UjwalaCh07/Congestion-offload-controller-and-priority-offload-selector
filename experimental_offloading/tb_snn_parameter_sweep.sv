`timescale 1ns/1ps

package snn_sweep_config_pkg;
    function automatic integer fast_threshold(input integer id);
        case (id)
            1: fast_threshold = 3;
            2: fast_threshold = 5;
            default: fast_threshold = 4;
        endcase
    endfunction

    function automatic integer pressure_threshold(input integer id);
        case (id)
            3: pressure_threshold = 3;
            4: pressure_threshold = 5;
            default: pressure_threshold = 4;
        endcase
    endfunction

    function automatic integer output_threshold(input integer id);
        case (id)
            5: output_threshold = 4;
            6: output_threshold = 8;
            default: output_threshold = 6;
        endcase
    endfunction

    function automatic integer fast_trend_weight(input integer id);
        case (id)
            7: fast_trend_weight = 1;
            8: fast_trend_weight = 3;
            default: fast_trend_weight = 2;
        endcase
    endfunction

    function automatic integer fast_traffic_weight(input integer id);
        case (id)
            9: fast_traffic_weight = 1;
            10: fast_traffic_weight = 3;
            default: fast_traffic_weight = 2;
        endcase
    endfunction

    function automatic integer pressure_occupancy_weight(input integer id);
        case (id)
            11: pressure_occupancy_weight = 1;
            12: pressure_occupancy_weight = 3;
            default: pressure_occupancy_weight = 2;
        endcase
    endfunction

    function automatic integer pressure_history_weight(input integer id);
        case (id)
            13: pressure_history_weight = 1;
            14: pressure_history_weight = 3;
            default: pressure_history_weight = 2;
        endcase
    endfunction

    function automatic integer output_fast_weight(input integer id);
        case (id)
            15: output_fast_weight = 2;
            16: output_fast_weight = 6;
            default: output_fast_weight = 4;
        endcase
    endfunction

    function automatic integer output_pressure_weight(input integer id);
        case (id)
            17: output_pressure_weight = 2;
            18: output_pressure_weight = 6;
            default: output_pressure_weight = 4;
        endcase
    endfunction

    function automatic integer leak_per_observation(input integer id);
        case (id)
            19: leak_per_observation = 0;
            20: leak_per_observation = 2;
            default: leak_per_observation = 1;
        endcase
    endfunction
endpackage

module tb_snn_parameter_sweep;
    localparam integer DIRECTIONS = snn_traffic_traces::DIRECTIONS;
    localparam integer CONFIG_COUNT = 21;
    localparam integer TRACE_COUNT = snn_traffic_traces::TRACE_COUNT;
    localparam integer TRACE_LENGTH = snn_traffic_traces::TRACE_LENGTH;
    localparam integer HORIZON = snn_traffic_traces::HORIZON;
    localparam integer SCORED_WINDOWS = TRACE_LENGTH - HORIZON;
    localparam integer OCCUPANCY_THRESHOLD_FOR_LABEL =
        snn_traffic_traces::OCCUPANCY_EVENT_THRESHOLD;
    localparam integer TUNING_FIRST = 0;
    localparam integer TUNING_LAST =
        snn_traffic_traces::TUNING_TRACE_COUNT - 1;
    localparam integer HELDOUT_FIRST =
        snn_traffic_traces::TUNING_TRACE_COUNT;
    localparam integer HELDOUT_LAST = TRACE_COUNT - 1;
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
    logic [DIRECTIONS-1:0] prediction_valid [0:CONFIG_COUNT-1];
    logic [DIRECTIONS-1:0] predicted_congestion [0:CONFIG_COUNT-1];
    logic [DIRECTIONS-1:0][7:0] prediction_activity [0:CONFIG_COUNT-1];

    integer tp [0:CONFIG_COUNT-1][0:1];
    integer fp [0:CONFIG_COUNT-1][0:1];
    integer tn [0:CONFIG_COUNT-1][0:1];
    integer fn [0:CONFIG_COUNT-1][0:1];
    integer early_sum [0:CONFIG_COUNT-1][0:1];
    integer early_count [0:CONFIG_COUNT-1][0:1];
    integer early_eligible_count [0:CONFIG_COUNT-1][0:1];
    integer delay_sum [0:CONFIG_COUNT-1][0:1];
    integer delay_count [0:CONFIG_COUNT-1][0:1];
    integer detection_eligible_count [0:CONFIG_COUNT-1][0:1];
    integer positive_labels [0:1];
    integer negative_labels [0:1];
    integer scored_windows [0:1];
    integer scenario_crossing [0:DIRECTIONS-1];
    integer pair_early_index [0:CONFIG_COUNT-1][0:DIRECTIONS-1];
    integer pair_detection_index [0:CONFIG_COUNT-1][0:DIRECTIONS-1];
    integer check_count = 0;
    integer selected_config = -1;
    integer selected_f1_score = -1;

    always #5 clk = ~clk;

    for (genvar config_id = 0; config_id < CONFIG_COUNT; config_id++) begin : g_sweep
        localparam integer FAST_T =
            snn_sweep_config_pkg::fast_threshold(config_id);
        localparam integer PRESSURE_T =
            snn_sweep_config_pkg::pressure_threshold(config_id);
        localparam integer OUTPUT_T =
            snn_sweep_config_pkg::output_threshold(config_id);
        localparam integer FAST_TREND_W =
            snn_sweep_config_pkg::fast_trend_weight(config_id);
        localparam integer FAST_TRAFFIC_W =
            snn_sweep_config_pkg::fast_traffic_weight(config_id);
        localparam integer PRESSURE_OCC_W =
            snn_sweep_config_pkg::pressure_occupancy_weight(config_id);
        localparam integer PRESSURE_HISTORY_W =
            snn_sweep_config_pkg::pressure_history_weight(config_id);
        localparam integer OUTPUT_FAST_W =
            snn_sweep_config_pkg::output_fast_weight(config_id);
        localparam integer OUTPUT_PRESSURE_W =
            snn_sweep_config_pkg::output_pressure_weight(config_id);
        localparam integer LEAK =
            snn_sweep_config_pkg::leak_per_observation(config_id);

        snn_congestion_predictor #(
            .NUM_DIRECTIONS(DIRECTIONS),
            .OCCUPANCY_WIDTH(4),
            .TRAFFIC_COUNT_WIDTH(4),
            .MEMBRANE_WIDTH(8),
            .OCCUPANCY_THRESHOLD(8),
            .TRAFFIC_THRESHOLD(4),
            .FAST_NEURON_THRESHOLD(FAST_T),
            .PRESSURE_NEURON_THRESHOLD(PRESSURE_T),
            .OUTPUT_NEURON_THRESHOLD(OUTPUT_T),
            .FAST_TREND_WEIGHT(FAST_TREND_W),
            .FAST_TRAFFIC_WEIGHT(FAST_TRAFFIC_W),
            .PRESSURE_OCCUPANCY_WEIGHT(PRESSURE_OCC_W),
            .PRESSURE_HISTORY_WEIGHT(PRESSURE_HISTORY_W),
            .OUTPUT_FAST_WEIGHT(OUTPUT_FAST_W),
            .OUTPUT_PRESSURE_WEIGHT(OUTPUT_PRESSURE_W),
            .LEAK_PER_OBSERVATION(LEAK)
        ) dut (
            .clk,
            .rst_n,
            .feature_valid,
            .occupancy,
            .occupancy_trend,
            .traffic_count,
            .recent_congestion,
            .prediction_valid(prediction_valid[config_id]),
            .predicted_congestion(predicted_congestion[config_id]),
            .prediction_activity(prediction_activity[config_id])
        );
    end

    function automatic integer trace_occupancy(
        input integer trace_id,
        input integer direction,
        input integer index
    );
        trace_occupancy =
            snn_traffic_traces::trace_occupancy(trace_id, direction, index);
    endfunction

    function automatic integer trace_traffic(
        input integer trace_id,
        input integer direction,
        input integer index
    );
        trace_traffic =
            snn_traffic_traces::trace_traffic(trace_id, direction, index);
    endfunction

    function automatic logic trace_history(
        input integer trace_id,
        input integer direction,
        input integer index
    );
        trace_history =
            snn_traffic_traces::trace_history(trace_id, direction, index);
    endfunction

    function automatic integer first_crossing(
        input integer trace_id,
        input integer direction
    );
        first_crossing = snn_traffic_traces::first_crossing(trace_id, direction);
    endfunction

    function automatic logic future_event(
        input integer trace_id,
        input integer direction,
        input integer index
    );
        future_event = snn_traffic_traces::future_event(
            trace_id, direction, index);
    endfunction

    function automatic logic trace_is_rising(
        input integer trace_id,
        input integer direction,
        input integer index
    );
        trace_is_rising =
            snn_traffic_traces::trace_is_rising(trace_id, direction, index);
    endfunction

    task automatic check(input logic condition, input string message);
        begin
            check_count++;
            if (condition !== 1'b1) begin
                $error("CHECK FAILED: %s at %0t", message, $time);
                $fatal(1);
            end
        end
    endtask

    task automatic reset_predictors;
        integer config_id;
        begin
            @(negedge clk);
            rst_n = 1'b0;
            feature_valid = '0;
            #1;
            for (config_id = 0; config_id < CONFIG_COUNT; config_id++) begin
                check(prediction_valid[config_id] == '0
                      && predicted_congestion[config_id] == '0
                      && prediction_activity[config_id] == '0,
                      "reset clears each sweep configuration");
            end
            @(posedge clk);
            #1;
            @(negedge clk);
            rst_n = 1'b1;
        end
    endtask

    task automatic run_scenario(
        input integer scenario,
        input integer group_id,
        input integer chosen_config
    );
        integer crossing;
        integer config_id;
        integer direction;
        logic truth;
        logic prediction;
        begin
            for (direction = 0; direction < DIRECTIONS; direction++) begin
                scenario_crossing[direction] = first_crossing(scenario, direction);
            end
            for (config_id = 0; config_id < CONFIG_COUNT; config_id++) begin
                for (direction = 0; direction < DIRECTIONS; direction++) begin
                    pair_early_index[config_id][direction] = -1;
                    pair_detection_index[config_id][direction] = -1;
                end
            end

            for (integer index = 0; index < SCORED_WINDOWS; index++) begin
                @(negedge clk);
                feature_valid = '1;
                for (direction = 0; direction < DIRECTIONS; direction++) begin
                    occupancy[direction] =
                        trace_occupancy(scenario, direction, index);
                    traffic_count[direction] =
                        trace_traffic(scenario, direction, index);
                    recent_congestion[direction] =
                        trace_history(scenario, direction, index);
                    if (trace_is_rising(scenario, direction, index))
                        occupancy_trend[direction] = TREND_RISING;
                    else if (index > 0
                        && trace_occupancy(scenario, direction, index)
                            < trace_occupancy(scenario, direction, index - 1))
                        occupancy_trend[direction] = TREND_FALLING;
                    else
                        occupancy_trend[direction] = TREND_STABLE;
                end

                @(posedge clk);
                #1;
                for (config_id = 0; config_id < CONFIG_COUNT; config_id++) begin
                    check(prediction_valid[config_id] == '1,
                          "each configuration samples every valid observation");
                end
                scored_windows[group_id]++;

                for (direction = 0; direction < DIRECTIONS; direction++) begin
                    truth = future_event(scenario, direction, index);
                    if (truth) positive_labels[group_id]++;
                    else negative_labels[group_id]++;

                    crossing = scenario_crossing[direction];
                    for (config_id = 0; config_id < CONFIG_COUNT; config_id++) begin
                        if (group_id == 0 || config_id == chosen_config) begin
                            prediction = predicted_congestion[config_id][direction];
                            if (truth) begin
                                if (prediction) tp[config_id][group_id]++;
                                else fn[config_id][group_id]++;
                            end else begin
                                if (prediction) fp[config_id][group_id]++;
                                else tn[config_id][group_id]++;
                            end

                            if (truth && prediction && crossing < TRACE_LENGTH
                                && index < crossing
                                && pair_early_index[config_id][direction] < 0)
                                pair_early_index[config_id][direction] = index;
                            if (crossing < SCORED_WINDOWS && index >= crossing
                                && prediction
                                && pair_detection_index[config_id][direction] < 0)
                                pair_detection_index[config_id][direction] = index;
                        end
                    end
                end
            end

            for (config_id = 0; config_id < CONFIG_COUNT; config_id++) begin
                if (group_id == 0 || config_id == chosen_config) begin
                    for (direction = 0; direction < DIRECTIONS; direction++) begin
                        crossing = scenario_crossing[direction];
                        if (crossing < TRACE_LENGTH
                            && pair_early_index[config_id][direction] >= 0) begin
                            early_sum[config_id][group_id] += crossing
                                - pair_early_index[config_id][direction];
                            early_count[config_id][group_id]++;
                        end
                        if (crossing > 0 && crossing < TRACE_LENGTH)
                            early_eligible_count[config_id][group_id]++;
                        if (crossing < SCORED_WINDOWS
                            && pair_detection_index[config_id][direction] >= 0) begin
                            delay_sum[config_id][group_id] +=
                                pair_detection_index[config_id][direction] - crossing;
                            delay_count[config_id][group_id]++;
                        end
                        if (crossing < SCORED_WINDOWS)
                            detection_eligible_count[config_id][group_id]++;
                    end
                end
            end
        end
    endtask

    task automatic print_metrics(
        input integer config_id,
        input integer group_id,
        input string group_name
    );
        integer predicted_positive;
        integer actual_positive;
        integer actual_negative;
        real precision;
        real recall;
        real false_positive_rate;
        real lead_average;
        real delay_average;
        begin
            predicted_positive = tp[config_id][group_id] + fp[config_id][group_id];
            actual_positive = tp[config_id][group_id] + fn[config_id][group_id];
            actual_negative = fp[config_id][group_id] + tn[config_id][group_id];
            $display("RESULT set=%s config=%0d TP=%0d FP=%0d TN=%0d FN=%0d",
                group_name, config_id, tp[config_id][group_id],
                fp[config_id][group_id], tn[config_id][group_id],
                fn[config_id][group_id]);
            if (predicted_positive == 0) $display("  precision=N/A (0 predicted positives)");
            else begin
                precision = 100.0 * tp[config_id][group_id] / predicted_positive;
                $display("  precision=%0.2f%%", precision);
            end
            if (actual_positive == 0) $display("  recall=N/A (0 positive labels)");
            else begin
                recall = 100.0 * tp[config_id][group_id] / actual_positive;
                $display("  recall=%0.2f%%", recall);
            end
            if (actual_negative == 0) $display("  false_positive_rate=N/A (0 negative labels)");
            else begin
                false_positive_rate =
                    100.0 * fp[config_id][group_id] / actual_negative;
                $display("  false_positive_rate=%0.2f%%", false_positive_rate);
            end
            if (early_count[config_id][group_id] == 0)
                $display("  early_warning=N/A (0 warnings; eligible_pairs=%0d)",
                    early_eligible_count[config_id][group_id]);
            else begin
                lead_average = 1.0 * early_sum[config_id][group_id]
                    / early_count[config_id][group_id];
                $display("  early_warning_pairs=%0d/%0d lead_total=%0d average=%0.2f windows",
                    early_count[config_id][group_id],
                    early_eligible_count[config_id][group_id],
                    early_sum[config_id][group_id], lead_average);
            end
            if (delay_count[config_id][group_id] == 0)
                $display("  detection_delay=N/A (0 detections; eligible_crossings=%0d)",
                    detection_eligible_count[config_id][group_id]);
            else begin
                delay_average = 1.0 * delay_sum[config_id][group_id]
                    / delay_count[config_id][group_id];
                $display("  detection_pairs=%0d/%0d delay_total=%0d average=%0.2f windows",
                    delay_count[config_id][group_id],
                    detection_eligible_count[config_id][group_id],
                    delay_sum[config_id][group_id], delay_average);
            end
        end
    endtask

    initial begin : p_sweep
        integer candidate_score;
        integer candidate_denominator;
        integer current_fp;
        integer best_fp;
        integer best_tp;

        for (integer config_id = 0; config_id < CONFIG_COUNT; config_id++) begin
            for (integer group_id = 0; group_id < 2; group_id++) begin
                tp[config_id][group_id] = 0;
                fp[config_id][group_id] = 0;
                tn[config_id][group_id] = 0;
                fn[config_id][group_id] = 0;
                early_sum[config_id][group_id] = 0;
                early_count[config_id][group_id] = 0;
                early_eligible_count[config_id][group_id] = 0;
                delay_sum[config_id][group_id] = 0;
                delay_count[config_id][group_id] = 0;
                detection_eligible_count[config_id][group_id] = 0;
            end
        end
        positive_labels[0] = 0;
        positive_labels[1] = 0;
        negative_labels[0] = 0;
        negative_labels[1] = 0;
        scored_windows[0] = 0;
        scored_windows[1] = 0;

        reset_predictors();
        for (integer scenario = TUNING_FIRST; scenario <= TUNING_LAST; scenario++) begin
            reset_predictors();
            run_scenario(scenario, 0, -1);
        end

        check(scored_windows[0] == snn_traffic_traces::TUNING_TRACE_COUNT
              * SCORED_WINDOWS,
              "tuning set scores exactly its designated samples");
        for (integer config_id = 0; config_id < CONFIG_COUNT; config_id++) begin
            check(tp[config_id][0] + fp[config_id][0]
                  + tn[config_id][0] + fn[config_id][0]
                  == scored_windows[0] * DIRECTIONS,
                  "each tuning configuration accounts for every scored direction-window");
            check(tp[config_id][0] + fn[config_id][0] == positive_labels[0]
                  && fp[config_id][0] + tn[config_id][0] == negative_labels[0],
                  "every tuning configuration shares the same labels");
            check(early_count[config_id][0] <= early_eligible_count[config_id][0]
                  && delay_count[config_id][0] <= detection_eligible_count[config_id][0],
                  "tuning timing counts do not exceed eligible crossings");
        end

        $display("SWEEP_CONFIGS=%0d TUNING_TRACES=%0d TUNING_DIRECTION_WINDOWS=%0d",
            CONFIG_COUNT, snn_traffic_traces::TUNING_TRACE_COUNT,
            scored_windows[0] * DIRECTIONS);
        $display("SPLIT: complete trace families 0-5 are tuning; families 6-7 are held out.");
        $display("Selection objective: maximize tuning micro-F1; ties choose fewer FP, then higher TP, then lower config ID.");
        for (integer config_id = 0; config_id < CONFIG_COUNT; config_id++) begin
            candidate_denominator = 2 * tp[config_id][0]
                + fp[config_id][0] + fn[config_id][0];
            candidate_score = (candidate_denominator == 0) ? 0
                : (2000000 * tp[config_id][0]) / candidate_denominator;
            current_fp = fp[config_id][0];
            if (config_id == 0 || candidate_score > selected_f1_score
                || (candidate_score == selected_f1_score && current_fp < best_fp)
                || (candidate_score == selected_f1_score && current_fp == best_fp
                    && tp[config_id][0] > best_tp)) begin
                selected_config = config_id;
                selected_f1_score = candidate_score;
                best_fp = current_fp;
                best_tp = tp[config_id][0];
            end
            $display("TUNING config=%0d FAST_T=%0d PRESSURE_T=%0d OUTPUT_T=%0d FAST_TREND_W=%0d FAST_TRAFFIC_W=%0d PRESSURE_OCC_W=%0d PRESSURE_HISTORY_W=%0d OUTPUT_FAST_W=%0d OUTPUT_PRESSURE_W=%0d LEAK=%0d F1_millionths=%0d TP=%0d FP=%0d TN=%0d FN=%0d EARLY=%0d/%0d/%0d DELAY=%0d/%0d/%0d",
                config_id,
                snn_sweep_config_pkg::fast_threshold(config_id),
                snn_sweep_config_pkg::pressure_threshold(config_id),
                snn_sweep_config_pkg::output_threshold(config_id),
                snn_sweep_config_pkg::fast_trend_weight(config_id),
                snn_sweep_config_pkg::fast_traffic_weight(config_id),
                snn_sweep_config_pkg::pressure_occupancy_weight(config_id),
                snn_sweep_config_pkg::pressure_history_weight(config_id),
                snn_sweep_config_pkg::output_fast_weight(config_id),
                snn_sweep_config_pkg::output_pressure_weight(config_id),
                snn_sweep_config_pkg::leak_per_observation(config_id),
                candidate_score, tp[config_id][0], fp[config_id][0],
                tn[config_id][0], fn[config_id][0],
                early_sum[config_id][0], early_count[config_id][0],
                early_eligible_count[config_id][0],
                delay_sum[config_id][0], delay_count[config_id][0],
                detection_eligible_count[config_id][0]);
            print_metrics(config_id, 0, "tuning");
        end
        $display("SELECTED_CONFIG=%0d TUNING_F1_millionths=%0d",
            selected_config, selected_f1_score);

        for (integer scenario = HELDOUT_FIRST; scenario <= HELDOUT_LAST; scenario++) begin
            reset_predictors();
            run_scenario(scenario, 1, selected_config);
        end

        check(scored_windows[1] == snn_traffic_traces::HELDOUT_TRACE_COUNT
              * SCORED_WINDOWS,
              "held-out set scores exactly its designated samples");
        check(tp[selected_config][1] + fp[selected_config][1]
              + tn[selected_config][1] + fn[selected_config][1]
              == scored_windows[1] * DIRECTIONS,
              "selected held-out configuration accounts for every scored direction-window");
        check(tp[selected_config][1] + fn[selected_config][1] == positive_labels[1]
              && fp[selected_config][1] + tn[selected_config][1] == negative_labels[1],
              "selected held-out configuration uses the held-out labels exactly once");
        check(early_count[selected_config][1]
                  <= early_eligible_count[selected_config][1]
              && delay_count[selected_config][1]
                  <= detection_eligible_count[selected_config][1],
              "held-out timing counts do not exceed eligible crossings");
        $display("HELDOUT_TRACES=%0d HELDOUT_DIRECTION_WINDOWS=%0d",
            snn_traffic_traces::HELDOUT_TRACE_COUNT,
            scored_windows[1] * DIRECTIONS);
        print_metrics(selected_config, 1, "heldout");
        $display("PASS: %0d parameter-sweep checks completed", check_count);
        $finish;
    end
endmodule
