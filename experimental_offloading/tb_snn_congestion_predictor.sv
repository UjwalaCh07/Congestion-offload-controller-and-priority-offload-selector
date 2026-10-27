`timescale 1ns/1ps

module tb_snn_congestion_predictor;
    localparam int OCC_STABLE = 1;
    localparam int OCC_FALLING = 0;
    localparam int OCC_RISING = 2;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic [1:0] feature_valid = '0;
    logic [1:0][3:0] occupancy = '0;
    logic [1:0][1:0] occupancy_trend = '0;
    logic [1:0][3:0] traffic_count = '0;
    logic [1:0] recent_congestion = '0;
    logic [1:0] prediction_valid;
    logic [1:0] predicted_congestion;
    logic [1:0][7:0] prediction_activity;

    logic [0:0] boundary_valid = '0;
    logic [0:0][3:0] boundary_occupancy = '0;
    logic [0:0][1:0] boundary_trend = '0;
    logic [0:0][3:0] boundary_traffic = '0;
    logic [0:0] boundary_history = '0;
    logic [0:0] boundary_prediction_valid;
    logic [0:0] boundary_prediction;
    logic [0:0][2:0] boundary_activity;

    logic [0:0] minimum_valid = '0;
    logic [0:0][0:0] minimum_occupancy = '0;
    logic [0:0][1:0] minimum_trend = '0;
    logic [0:0][0:0] minimum_traffic = '0;
    logic [0:0] minimum_history = '0;
    logic [0:0] minimum_prediction_valid;
    logic [0:0] minimum_prediction;
    logic [0:0][1:0] minimum_activity;

    logic [0:0] isolated_valid = '0;
    logic [0:0][3:0] isolated_occupancy = '0;
    logic [0:0][1:0] isolated_trend = '0;
    logic [0:0][3:0] isolated_traffic = '0;
    logic [0:0] isolated_history = '0;
    logic [0:0] fast_only_prediction;
    logic [0:0][2:0] fast_only_activity;
    logic [0:0] pressure_only_prediction;
    logic [0:0][2:0] pressure_only_activity;

    integer checks = 0;

    always #5 clk = ~clk;

    snn_congestion_predictor #(
        .NUM_DIRECTIONS(2)
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

    snn_congestion_predictor #(
        .NUM_DIRECTIONS(1),
        .OCCUPANCY_WIDTH(4),
        .TRAFFIC_COUNT_WIDTH(4),
        .MEMBRANE_WIDTH(3),
        .OCCUPANCY_THRESHOLD(8),
        .TRAFFIC_THRESHOLD(4),
        .FAST_NEURON_THRESHOLD(4),
        .PRESSURE_NEURON_THRESHOLD(4),
        .OUTPUT_NEURON_THRESHOLD(6),
        .FAST_TREND_WEIGHT(2),
        .FAST_TRAFFIC_WEIGHT(2),
        .PRESSURE_OCCUPANCY_WEIGHT(2),
        .PRESSURE_HISTORY_WEIGHT(2),
        .OUTPUT_FAST_WEIGHT(6),
        .OUTPUT_PRESSURE_WEIGHT(6),
        .LEAK_PER_OBSERVATION(1)
    ) boundary_dut (
        .clk,
        .rst_n,
        .feature_valid(boundary_valid),
        .occupancy(boundary_occupancy),
        .occupancy_trend(boundary_trend),
        .traffic_count(boundary_traffic),
        .recent_congestion(boundary_history),
        .prediction_valid(boundary_prediction_valid),
        .predicted_congestion(boundary_prediction),
        .prediction_activity(boundary_activity)
    );

    snn_congestion_predictor #(
        .NUM_DIRECTIONS(1),
        .OCCUPANCY_WIDTH(1),
        .TRAFFIC_COUNT_WIDTH(1),
        .MEMBRANE_WIDTH(2),
        .OCCUPANCY_THRESHOLD(1),
        .TRAFFIC_THRESHOLD(1),
        .FAST_NEURON_THRESHOLD(1),
        .PRESSURE_NEURON_THRESHOLD(1),
        .OUTPUT_NEURON_THRESHOLD(1),
        .FAST_TREND_WEIGHT(1),
        .FAST_TRAFFIC_WEIGHT(1),
        .PRESSURE_OCCUPANCY_WEIGHT(1),
        .PRESSURE_HISTORY_WEIGHT(1),
        .OUTPUT_FAST_WEIGHT(1),
        .OUTPUT_PRESSURE_WEIGHT(1),
        .LEAK_PER_OBSERVATION(0)
    ) minimum_dut (
        .clk,
        .rst_n,
        .feature_valid(minimum_valid),
        .occupancy(minimum_occupancy),
        .occupancy_trend(minimum_trend),
        .traffic_count(minimum_traffic),
        .recent_congestion(minimum_history),
        .prediction_valid(minimum_prediction_valid),
        .predicted_congestion(minimum_prediction),
        .prediction_activity(minimum_activity)
    );

    snn_congestion_predictor #(
        .NUM_DIRECTIONS(1),
        .MEMBRANE_WIDTH(3),
        .OCCUPANCY_THRESHOLD(8),
        .TRAFFIC_THRESHOLD(4),
        .FAST_NEURON_THRESHOLD(4),
        .PRESSURE_NEURON_THRESHOLD(4),
        .OUTPUT_NEURON_THRESHOLD(6),
        .FAST_TREND_WEIGHT(2),
        .FAST_TRAFFIC_WEIGHT(2),
        .PRESSURE_OCCUPANCY_WEIGHT(0),
        .PRESSURE_HISTORY_WEIGHT(0),
        .OUTPUT_FAST_WEIGHT(6),
        .OUTPUT_PRESSURE_WEIGHT(0),
        .LEAK_PER_OBSERVATION(1)
    ) fast_only_dut (
        .clk,
        .rst_n,
        .feature_valid(isolated_valid),
        .occupancy(isolated_occupancy),
        .occupancy_trend(isolated_trend),
        .traffic_count(isolated_traffic),
        .recent_congestion(isolated_history),
        .prediction_valid(),
        .predicted_congestion(fast_only_prediction),
        .prediction_activity(fast_only_activity)
    );

    snn_congestion_predictor #(
        .NUM_DIRECTIONS(1),
        .MEMBRANE_WIDTH(3),
        .OCCUPANCY_THRESHOLD(8),
        .TRAFFIC_THRESHOLD(4),
        .FAST_NEURON_THRESHOLD(4),
        .PRESSURE_NEURON_THRESHOLD(4),
        .OUTPUT_NEURON_THRESHOLD(6),
        .FAST_TREND_WEIGHT(0),
        .FAST_TRAFFIC_WEIGHT(0),
        .PRESSURE_OCCUPANCY_WEIGHT(2),
        .PRESSURE_HISTORY_WEIGHT(2),
        .OUTPUT_FAST_WEIGHT(0),
        .OUTPUT_PRESSURE_WEIGHT(6),
        .LEAK_PER_OBSERVATION(1)
    ) pressure_only_dut (
        .clk,
        .rst_n,
        .feature_valid(isolated_valid),
        .occupancy(isolated_occupancy),
        .occupancy_trend(isolated_trend),
        .traffic_count(isolated_traffic),
        .recent_congestion(isolated_history),
        .prediction_valid(),
        .predicted_congestion(pressure_only_prediction),
        .prediction_activity(pressure_only_activity)
    );

    task automatic check(input logic condition, input string message);
        begin
            checks = checks + 1;
            if (condition !== 1'b1) begin
                $error("CHECK FAILED: %s at %0t", message, $time);
                $fatal(1);
            end
        end
    endtask

    task automatic sample_features(
        input logic [1:0] valid,
        input logic [3:0] occ0,
        input logic [1:0] trend0,
        input logic [3:0] traffic0,
        input logic history0,
        input logic [3:0] occ1,
        input logic [1:0] trend1,
        input logic [3:0] traffic1,
        input logic history1
    );
        begin
            @(negedge clk);
            feature_valid = valid;
            occupancy[0] = occ0;
            occupancy_trend[0] = trend0;
            traffic_count[0] = traffic0;
            recent_congestion[0] = history0;
            occupancy[1] = occ1;
            occupancy_trend[1] = trend1;
            traffic_count[1] = traffic1;
            recent_congestion[1] = history1;
            @(posedge clk);
            #1;
        end
    endtask

    task automatic reset_predictors;
        begin
            @(negedge clk);
            rst_n = 1'b0;
            feature_valid = '0;
            boundary_valid = '0;
            minimum_valid = '0;
            isolated_valid = '0;
            #1;
            check(predicted_congestion == '0 && prediction_activity == '0
                  && prediction_valid == '0,
                  "asynchronous reset clears primary outputs");
            check(boundary_prediction == '0 && boundary_activity == '0
                  && boundary_prediction_valid == '0,
                  "asynchronous reset clears boundary outputs");
            check(minimum_prediction == '0 && minimum_activity == '0
                  && minimum_prediction_valid == '0,
                  "asynchronous reset clears minimum-width outputs");
            check(fast_only_prediction == '0 && fast_only_activity == '0
                  && pressure_only_prediction == '0 && pressure_only_activity == '0,
                  "asynchronous reset clears both isolated-neuron test instances");
            @(posedge clk);
            #1;
            @(negedge clk);
            rst_n = 1'b1;
        end
    endtask

    initial begin
        reset_predictors();
        check(predicted_congestion == '0 && prediction_activity == '0,
              "reset starts from deterministic no-warning state");

        repeat (4) begin
            sample_features(2'b11, 0, OCC_STABLE, 0, 0,
                            0, OCC_STABLE, 0, 0);
            check(prediction_valid == 2'b11,
                  "valid indication marks each sampled observation window");
            check(predicted_congestion == '0 && prediction_activity == '0,
                  "low stable occupancy and traffic remain quiescent");
        end

        sample_features(2'b00, 4'd15, OCC_RISING, 4'd15, 1'b1,
                        4'd15, OCC_RISING, 4'd15, 1'b1);
        check(prediction_valid == '0,
              "invalid feature window does not update prediction outputs");
        check(predicted_congestion == '0 && prediction_activity == '0,
              "repeated values without feature_valid do not accumulate");

        sample_features(2'b01, 3, OCC_RISING, 4, 0,
                        0, OCC_STABLE, 0, 0);
        check(prediction_valid == 2'b01,
              "per-direction update pulse updates only valid direction");
        check(!predicted_congestion[0] && prediction_activity[0] == 4,
              "first rising-traffic input raises output membrane below threshold");
        check(prediction_activity[1] == 0,
              "invalid direction retains independent membrane and score");

        sample_features(2'b01, 4, OCC_RISING, 4, 0,
                        0, OCC_STABLE, 0, 0);
        check(predicted_congestion[0] && prediction_activity[0] == 7,
              "repeated rising traffic integrates to the output spike threshold");
        check(!predicted_congestion[1] && prediction_activity[1] == 0,
              "unobserved direction does not inherit another direction's spike");

        sample_features(2'b10, 0, OCC_STABLE, 0, 0,
                        0, OCC_RISING, 4, 0);
        check(prediction_valid == 2'b10 && !predicted_congestion[1]
              && prediction_activity[1] == 4,
              "second direction responds independently when its window is valid");

        reset_predictors();
        sample_features(2'b01, 4, OCC_RISING, 4, 0,
                        0, OCC_STABLE, 0, 0);
        check(prediction_activity[0] == 4 && !predicted_congestion[0],
              "single fast-neuron spike produces sub-threshold readout activity");
        sample_features(2'b01, 3, OCC_FALLING, 0, 0,
                        0, OCC_STABLE, 0, 0);
        check(prediction_activity[0] == 3 && !predicted_congestion[0],
              "one observation interval of leak reduces activity by one");
        sample_features(2'b01, 3, OCC_STABLE, 0, 0,
                        0, OCC_STABLE, 0, 0);
        check(prediction_activity[0] == 2,
              "readout membrane continues to leak on later valid observations");
        sample_features(2'b01, 3, OCC_STABLE, 0, 0,
                        0, OCC_STABLE, 0, 0);
        check(prediction_activity[0] == 1 && !predicted_congestion[0],
              "readout leak approaches zero without crossing below it");
        sample_features(2'b01, 3, OCC_STABLE, 0, 0,
                        0, OCC_STABLE, 0, 0);
        check(prediction_activity[0] == 0 && !predicted_congestion[0],
              "readout membrane clamps at zero when leak exceeds remaining activity");
        sample_features(2'b01, 3, OCC_STABLE, 0, 0,
                        0, OCC_STABLE, 0, 0);
        check(prediction_activity[0] == 0,
              "zero activity remains zero under repeated leak");

        reset_predictors();
        repeat (2) begin
            sample_features(2'b01, 4'd8, OCC_STABLE, 0, 1'b1,
                            0, OCC_STABLE, 0, 0);
        end
        check(predicted_congestion[0],
              "sustained high occupancy and recent-history features trigger prediction");
        sample_features(2'b01, 0, OCC_FALLING, 0, 0,
                        0, OCC_STABLE, 0, 0);
        check(!predicted_congestion[0] && prediction_activity[0] == 0,
              "falling occupancy and reduced traffic clear the pressure response");

        // The three-bit test instance receives simultaneous hidden spikes.
        // Its output accumulator exceeds seven, so the observable activity
        // saturates at the maximum representable potential.
        @(negedge clk);
        boundary_valid = 1'b1;
        boundary_occupancy[0] = 4'd8;
        boundary_trend[0] = OCC_RISING;
        boundary_traffic[0] = 4'd4;
        boundary_history[0] = 1'b1;
        @(posedge clk);
        #1;
        check(boundary_prediction_valid[0] && boundary_prediction[0]
              && boundary_activity[0] == 3'd7,
              "small membrane configuration saturates activity without overflow");
        repeat (3) begin
            @(negedge clk);
            @(posedge clk);
            #1;
            check(boundary_prediction_valid[0] && boundary_prediction[0]
                  && boundary_activity[0] == 3'd7,
                  "repeated simultaneous spikes stay saturated without overflow");
        end

        reset_predictors();
        @(negedge clk);
        isolated_valid[0] = 1'b1;
        isolated_occupancy[0] = 4'd8;
        isolated_trend[0] = OCC_RISING;
        isolated_traffic[0] = 4'd4;
        isolated_history[0] = 1'b1;
        @(posedge clk);
        #1;
        check(fast_only_prediction[0] && fast_only_activity[0] == 3'd6,
              "fast neuron independently drives output exactly to its threshold");
        check(pressure_only_prediction[0] && pressure_only_activity[0] == 3'd6,
              "pressure neuron independently drives output exactly to its threshold");
        @(negedge clk);
        isolated_valid[0] = 1'b0;
        @(posedge clk);
        #1;
        check(fast_only_prediction[0] && pressure_only_prediction[0],
              "isolated predictors hold output state when their feature is invalid");

        // Reset during active state clears outputs and all future response
        // history; low input after reset cannot create a stale warning.
        reset_predictors();
        sample_features(2'b11, 0, OCC_STABLE, 0, 0,
                        0, OCC_STABLE, 0, 0);
        check(predicted_congestion == '0 && prediction_activity == '0,
              "reset during activity removes prior prediction state");
        check(!fast_only_prediction[0] && fast_only_activity[0] == 0
              && !pressure_only_prediction[0] && pressure_only_activity[0] == 0,
              "reset clears fast and pressure history before subsequent low inputs");

        minimum_valid = 1'b1;
        minimum_occupancy[0] = 1'b1;
        minimum_trend[0] = OCC_RISING;
        minimum_traffic[0] = 1'b1;
        @(posedge clk);
        #1;
        check(minimum_prediction_valid[0] && minimum_prediction[0]
              && minimum_activity[0] == 2'd2,
              "minimum legal widths and threshold values operate without overflow");
        @(negedge clk);
        minimum_valid = 1'b0;
        @(posedge clk);
        #1;
        check(!minimum_prediction_valid[0] && minimum_prediction[0],
              "prediction holds between updates while valid deasserts");

        $display("PASS: %0d SNN checks completed", checks);
        $finish;
    end
endmodule

module tb_snn_invalid_parameter;
    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic [0:0] valid = '0;
    logic [0:0][0:0] occupancy = '0;
    logic [0:0][1:0] trend = '0;
    logic [0:0][3:0] traffic = '0;
    logic [0:0] history = '0;

    snn_congestion_predictor #(
        .NUM_DIRECTIONS(1),
        .OCCUPANCY_WIDTH(1),
        .TRAFFIC_COUNT_WIDTH(4),
        .OCCUPANCY_THRESHOLD(2)
    ) invalid_dut (
        .clk,
        .rst_n,
        .feature_valid(valid),
        .occupancy,
        .occupancy_trend(trend),
        .traffic_count(traffic),
        .recent_congestion(history),
        .prediction_valid(),
        .predicted_congestion(),
        .prediction_activity()
    );
endmodule
