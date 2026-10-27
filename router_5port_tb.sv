// Self-checking testbench for router_5port.
//
// Run from PowerShell in the project folder with:
//   iverilog -g2012 -s router_5port_tb -o router_5port_test rtl\noc_pkg.sv rtl\fifo.sv rtl\input_buffer.sv rtl\round_robin_arbiter.sv rtl\switch_allocator.sv rtl\crossbar.sv rtl\router_5port.sv rtl\router_5port_tb.sv
//   vvp router_5port_test
//   The simulation also records every signal transition in router_5port_tb.vcd.
//   The console transcript is also written to router_5port_results.txt.
//
// The testbench drives the same ready/valid signals a neighboring router
// would use and checks that accepted flits emerge from the correct output.
module router_5port_tb;
    localparam int NUMPORTS = 5;
    localparam int FLITWIDTH = 48;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic [NUMPORTS-1:0] in_valid = '0;
    logic [NUMPORTS-1:0] in_ready;
    logic [NUMPORTS-1:0][FLITWIDTH-1:0] in_flit = '0;
    logic [NUMPORTS-1:0] out_valid;
    logic [NUMPORTS-1:0] out_ready = '1;
    logic [NUMPORTS-1:0][FLITWIDTH-1:0] out_flit;
    logic [NUMPORTS-1:0] invalid_flit_dropped;

    int checks_passed = 0;
    integer results_file;
    localparam int MAX_TRACKED_FLITS = 1024;
    logic [FLITWIDTH-1:0] expected_flits [0:NUMPORTS-1][0:MAX_TRACKED_FLITS-1];
    int queue_read [0:NUMPORTS-1];
    int queue_write [0:NUMPORTS-1];
    int queue_count [0:NUMPORTS-1];
    logic [NUMPORTS-1:0] previous_invalid = '0;
    logic [NUMPORTS-1:0] input_stalled = '0;
    logic [NUMPORTS-1:0] output_stalled = '0;
    logic [FLITWIDTH-1:0] held_input_flit [0:NUMPORTS-1];
    logic [FLITWIDTH-1:0] held_output_flit [0:NUMPORTS-1];

    always #5 clk = ~clk;

    router_5port dut (.*);

    // Validate the signals between every router stage, not only the public
    // input/output behavior. The model also checks per-input FIFO ordering.
    task automatic check_stages(input string phase);
        logic [NUMPORTS-1:0] expected_requests;
        logic [FLITWIDTH-1:0] expected_output_flit;
        logic [2:0] destination;
        int grant_count;

        for (int input_port = 0; input_port < NUMPORTS; input_port++) begin
            if (dut.buffer_valid[input_port] !== (queue_count[input_port] != 0))
                $fatal(1, "FAIL (%s): input %0d FIFO valid=%b, expected %b",
                       phase, input_port, dut.buffer_valid[input_port],
                       queue_count[input_port] != 0);
            if (queue_count[input_port] != 0 &&
                dut.buffer_flit[input_port] !==
                    expected_flits[input_port][queue_read[input_port]])
                $fatal(1, "FAIL (%s): input %0d FIFO head=%h, expected %h",
                       phase, input_port, dut.buffer_flit[input_port],
                       expected_flits[input_port][queue_read[input_port]]);

            if (in_ready[input_port] !==
                ((queue_count[input_port] < noc_pkg::FIFO_DEPTH) ||
                 dut.buffer_pop[input_port]))
                $fatal(1, "FAIL (%s): input %0d ready does not match FIFO capacity/pop",
                       phase, input_port);

            expected_requests = '0;
            destination = dut.buffer_flit[input_port] >> (FLITWIDTH - 3);
            if (dut.buffer_valid[input_port]) begin
                if (destination < NUMPORTS)
                    expected_requests[destination] = 1'b1;
            end

            for (int output_port = 0; output_port < NUMPORTS; output_port++) begin
                if (dut.allocator.request[output_port * NUMPORTS + input_port] !==
                    expected_requests[output_port])
                    $fatal(1, "FAIL (%s): request mismatch input %0d -> output %0d",
                           phase, input_port, output_port);
            end

            if (dut.invalid_head[input_port] !==
                (dut.buffer_valid[input_port] &&
                 (destination >= NUMPORTS)))
                $fatal(1, "FAIL (%s): invalid-head decode mismatch on input %0d",
                       phase, input_port);
        end

        for (int output_port = 0; output_port < NUMPORTS; output_port++) begin
            grant_count = 0;
            expected_output_flit = '0;
            for (int input_port = 0; input_port < NUMPORTS; input_port++) begin
                if (dut.grant[output_port * NUMPORTS + input_port]) begin
                    grant_count++;
                    if (!dut.allocator.request[output_port * NUMPORTS + input_port])
                        $fatal(1, "FAIL (%s): grant is not backed by a request (%0d -> %0d)",
                               phase, input_port, output_port);
                    expected_output_flit = dut.buffer_flit[input_port];
                end
            end

            if (grant_count > 1)
                $fatal(1, "FAIL (%s): output %0d has %0d simultaneous grants",
                       phase, output_port, grant_count);
            if (dut.grant_valid[output_port] !== (grant_count != 0))
                $fatal(1, "FAIL (%s): grant_valid mismatch on output %0d",
                       phase, output_port);
            if (out_valid[output_port] !== dut.grant_valid[output_port])
                $fatal(1, "FAIL (%s): crossbar valid mismatch on output %0d",
                       phase, output_port);
            if (out_flit[output_port] !== expected_output_flit)
                $fatal(1, "FAIL (%s): crossbar data mismatch on output %0d; got %h expected %h",
                       phase, output_port, out_flit[output_port], expected_output_flit);
        end

        for (int input_port = 0; input_port < NUMPORTS; input_port++) begin
            begin : check_input_pop
                logic expected_pop;
                expected_pop = 1'b0;
                for (int output_port = 0; output_port < NUMPORTS; output_port++)
                    if (dut.grant[output_port * NUMPORTS + input_port] &&
                        out_ready[output_port])
                        expected_pop = 1'b1;
                if (dut.crossbar_pop[input_port] !== expected_pop)
                    $fatal(1, "FAIL (%s): crossbar pop mismatch on input %0d",
                           phase, input_port);
            end
            if (dut.buffer_pop[input_port] !==
                (dut.crossbar_pop[input_port] | dut.invalid_head[input_port]))
                $fatal(1, "FAIL (%s): FIFO pop mismatch on input %0d",
                       phase, input_port);
        end
        checks_passed++;
    endtask

    task automatic report_line(input string message);
        $display("%s", message);
        $fdisplay(results_file, "%s", message);
        $fflush(results_file);
    endtask

    task automatic record_test_pass();
        report_line("  PASS");
    endtask

    // At each active edge, compare transfers with the reference queues. A
    // trace line records all boundary handshakes and each active stage.
    always @(posedge clk) begin : p_stage_checker
        logic [NUMPORTS-1:0] popped;
        logic [NUMPORTS-1:0] invalid_this_edge;
        int selected_input;

        if (!rst_n) begin
            for (int input_port = 0; input_port < NUMPORTS; input_port++) begin
                queue_read[input_port] = 0;
                queue_write[input_port] = 0;
                queue_count[input_port] = 0;
            end
            previous_invalid = '0;
            input_stalled = '0;
            output_stalled = '0;
            invalid_this_edge = '0;
        end else begin
            check_stages("before clock edge");
            if (invalid_flit_dropped !== previous_invalid)
                $fatal(1, "FAIL: invalid-drop status does not match the previous cycle");

            for (int port = 0; port < NUMPORTS; port++) begin
                if (input_stalled[port] &&
                    (!in_valid[port] || in_flit[port] !== held_input_flit[port]))
                    $fatal(1, "FAIL: input %0d changed valid/data before ready", port);
                if (output_stalled[port] &&
                    (!out_valid[port] || out_flit[port] !== held_output_flit[port]))
                    $fatal(1, "FAIL: output %0d changed valid/data while stalled", port);
                input_stalled[port] = in_valid[port] && !in_ready[port];
                output_stalled[port] = out_valid[port] && !out_ready[port];
                held_input_flit[port] = in_flit[port];
                held_output_flit[port] = out_flit[port];
            end

            popped = '0;
            invalid_this_edge = dut.invalid_head;
            report_line($sformatf(
                "TRACE t=%0t in=%b ready=%b fifo_valid=%b requests=%b grants=%b out_valid=%b out_ready=%b invalid=%b",
                $time, in_valid, in_ready, dut.buffer_valid,
                dut.allocator.request, dut.grant, out_valid, out_ready,
                dut.invalid_head));

            for (int output_port = 0; output_port < NUMPORTS; output_port++) begin
                if (out_valid[output_port] && out_ready[output_port]) begin
                    selected_input = -1;
                    for (int input_port = 0; input_port < NUMPORTS; input_port++)
                        if (dut.grant[output_port * NUMPORTS + input_port])
                            selected_input = input_port;

                    if (selected_input < 0)
                        $fatal(1, "FAIL: output %0d transferred without a grant",
                               output_port);
                    if (queue_count[selected_input] == 0)
                        $fatal(1, "FAIL: output %0d transferred from empty input %0d",
                               output_port, selected_input);
                    if (out_flit[output_port] !==
                        expected_flits[selected_input][queue_read[selected_input]])
                        $fatal(1, "FAIL: output %0d received %h; input %0d expected head %h",
                               output_port, out_flit[output_port], selected_input,
                               expected_flits[selected_input][queue_read[selected_input]]);

                    report_line($sformatf(
                        "TRACE t=%0t crossbar input=%0d -> output=%0d flit=%h",
                        $time, selected_input, output_port, out_flit[output_port]));
                    popped[selected_input] = 1'b1;
                end
            end

            for (int input_port = 0; input_port < NUMPORTS; input_port++) begin
                if (invalid_this_edge[input_port]) begin
                    if (popped[input_port])
                        $fatal(1, "FAIL: invalid flit and crossbar transfer both popped input %0d",
                               input_port);
                    report_line($sformatf(
                        "TRACE t=%0t invalid flit dropped at input=%0d flit=%h",
                        $time, input_port, dut.buffer_flit[input_port]));
                    popped[input_port] = 1'b1;
                end

                if (popped[input_port]) begin
                    queue_read[input_port] =
                        (queue_read[input_port] + 1) % MAX_TRACKED_FLITS;
                    queue_count[input_port]--;
                end

                if (in_valid[input_port] && in_ready[input_port]) begin
                    if (queue_count[input_port] >= MAX_TRACKED_FLITS)
                        $fatal(1, "FAIL: reference queue overflow on input %0d",
                               input_port);
                    expected_flits[input_port][queue_write[input_port]] =
                        in_flit[input_port];
                    queue_write[input_port] =
                        (queue_write[input_port] + 1) % MAX_TRACKED_FLITS;
                    queue_count[input_port]++;
                    report_line($sformatf(
                        "TRACE t=%0t input accepted at port=%0d flit=%h",
                        $time, input_port, in_flit[input_port]));
                end
            end
            previous_invalid = invalid_this_edge;
        end

        #1;
        check_stages("after clock edge");
        if (invalid_flit_dropped !== invalid_this_edge)
            $fatal(1, "FAIL: invalid-drop pulse does not match this cycle's invalid heads");
    end

    // Pack a port number into [47:45] and a recognizable value into payload.
    function automatic logic [FLITWIDTH-1:0] make_flit(
        input logic [2:0] destination,
        input logic [44:0] payload
    );
        return {destination, payload};
    endfunction

    // Drive an input until a rising edge accepts its valid flit. The upstream
    // must keep valid/data stable until ready is also high.
    task automatic send_flit(
        input int source,
        input logic [FLITWIDTH-1:0] flit
    );
        @(negedge clk);
        in_flit[source] = flit;
        in_valid[source] = 1'b1;

        do begin
            @(posedge clk);
        end while (!in_ready[source]);

        // Deassert valid away from the active clock edge to avoid a testbench
        // race with the router's sequential FIFO logic.
        @(negedge clk);
        in_valid[source] = 1'b0;
    endtask

    // With the output ready, check the head flit and let the next rising edge
    // transfer it. The destination is an output port index, not an input index.
    task automatic expect_transfer(
        input int destination,
        input logic [FLITWIDTH-1:0] expected_flit
    );
        // Call after a sender task returns on a falling edge, or just after a
        // previous transfer's rising edge. Check before the next transfer edge.
        #1;
        if (!out_valid[destination])
            $fatal(1, "FAIL: expected valid flit on output %0d", destination);
        if (out_flit[destination] !== expected_flit)
            $fatal(1, "FAIL: output %0d expected %h, got %h",
                   destination, expected_flit, out_flit[destination]);
        if (!out_ready[destination])
            $fatal(1, "FAIL: test expected output %0d to be ready", destination);

        @(posedge clk);
        #1;
        checks_passed++;
    endtask

    // Watchdog prevents a broken handshake from hanging the simulation.
    initial begin
        $dumpfile("router_5port_tb.vcd");
        $dumpvars(0, router_5port_tb);
        repeat (500) @(posedge clk);
        $fatal(1, "FAIL: simulation timed out");
    end

    initial begin : run_tests
        logic [FLITWIDTH-1:0] flit_a;
        logic [FLITWIDTH-1:0] flit_b;

        results_file = $fopen("router_5port_results.txt", "w");
        if (results_file == 0)
            $fatal(1, "FAIL: unable to open router_5port_results.txt");
        report_line("Five-port router test results");
        report_line("");

        // Keep reset asserted for two clocks, then release it between edges.
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        // TEST 1: Several sources contend for Local. Source 1 wins first and
        // becomes locked while Local is stalled. Higher-priority source 0 then
        // arrives, but it must not replace source 1's already-offered flit.
        // After source 1 transfers, round-robin order serves source 3 then 0.
        report_line("TEST 1: FIFO, round-robin arbitration, and stable stalled grant");
        flit_a = make_flit(3'd0, 45'd101);
        flit_b = make_flit(3'd0, 45'd103);
        out_ready[0] = 1'b0;
        send_flit(1, flit_a);
        send_flit(3, flit_b);
        send_flit(0, make_flit(3'd0, 45'd100));
        #1;
        if (!out_valid[0] || out_flit[0] !== flit_a)
            $fatal(1, "FAIL: first Local grant should be source 1's flit");
        out_ready[0] = 1'b1;
        expect_transfer(0, flit_a);
        expect_transfer(0, flit_b);
        expect_transfer(0, make_flit(3'd0, 45'd100));
        record_test_pass();

        // TEST 2: Send packets to every destination and check they leave the
        // matching output. This confirms destination decoding and switch paths.
        report_line("TEST 2: all five destination routes");
        for (int destination = 0; destination < NUMPORTS; destination++) begin
            logic [FLITWIDTH-1:0] expected;
            int source;

            expected = make_flit(destination[2:0], 45'(200 + destination));
            // Make the East example especially clear: a flit enters Local
            // (input 0), but its destination bits send it out through East
            // (output 3). Other destinations use a different source input.
            source = (destination == 3) ? 0 : (destination + 1) % NUMPORTS;
            send_flit(source, expected);
            expect_transfer(destination, expected);
        end
        record_test_pass();

        // TEST 3: Two different outputs can transfer in parallel on one clock.
        report_line("TEST 3: simultaneous transfers on separate outputs");
        flit_a = make_flit(3'd2, 45'd302);
        flit_b = make_flit(3'd4, 45'd504);
        out_ready[2] = 1'b0;
        out_ready[4] = 1'b0;
        send_flit(0, flit_a);
        send_flit(2, flit_b);
        #1;
        if (!out_valid[2] || out_flit[2] !== flit_a ||
            !out_valid[4] || out_flit[4] !== flit_b)
            $fatal(1, "FAIL: expected simultaneous South and West flits");
        out_ready[2] = 1'b1;
        out_ready[4] = 1'b1;
        @(posedge clk);
        #1;
        checks_passed++;
        record_test_pass();

        // TEST 4: Fill one input FIFO while its destination is blocked. The
        // first flit must remain stable at the output and the fifth write must
        // be backpressured until the receiver starts accepting flits.
        report_line("TEST 4: output backpressure and input FIFO capacity");
        out_ready[1] = 1'b0;
        for (int item = 0; item < 4; item++)
            send_flit(2, make_flit(3'd1, 45'(400 + item)));

        @(negedge clk);
        if (in_ready[2])
            $fatal(1, "FAIL: full input FIFO should deassert in_ready");
        if (!out_valid[1] || out_flit[1] !== make_flit(3'd1, 45'd400))
            $fatal(1, "FAIL: blocked output should hold the oldest flit");
        repeat (2) begin
            @(negedge clk);
            if (!out_valid[1] || out_flit[1] !== make_flit(3'd1, 45'd400))
                $fatal(1, "FAIL: output flit changed under backpressure");
        end

        // On this edge the old head is removed and the fifth flit is written;
        // the FIFO supports both operations together without losing data.
        in_flit[2] = make_flit(3'd1, 45'd404);
        in_valid[2] = 1'b1;
        out_ready[1] = 1'b1;
        #1;
        if (!in_ready[2])
            $fatal(1, "FAIL: full FIFO should accept write when read frees a slot");
        @(posedge clk);
        #1;
        in_valid[2] = 1'b0;
        checks_passed++;

        for (int item = 1; item <= 4; item++)
            expect_transfer(1, make_flit(3'd1, 45'(400 + item)));
        record_test_pass();

        // TEST 5: Invalid destination codes (5, 6, or 7) are discarded and
        // reported rather than permanently blocking their source FIFO.
        report_line("TEST 5: invalid destination is discarded and reported");
        send_flit(4, make_flit(3'd7, 45'd707));
        @(posedge clk);
        #1;
        if (!invalid_flit_dropped[4])
            $fatal(1, "FAIL: invalid destination should pulse drop status");
        checks_passed++;
        @(posedge clk);
        #1;
        if (invalid_flit_dropped[4])
            $fatal(1, "FAIL: invalid destination status should last one cycle");
        record_test_pass();

        report_line($sformatf("ALL TESTS PASSED (%0d stage/transfer check points)",
                              checks_passed));
        $fclose(results_file);
        $finish;
    end
endmodule
