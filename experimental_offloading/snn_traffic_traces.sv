`timescale 1ns/1ps

package snn_traffic_traces;
    parameter integer DIRECTIONS = 2;
    parameter integer TRACE_COUNT = 32;
    parameter integer TRACE_LENGTH = 32;
    parameter integer HORIZON = 2;
    parameter integer OCCUPANCY_EVENT_THRESHOLD = 12;
    parameter integer TUNING_TRACE_COUNT = 24;
    parameter integer HELDOUT_TRACE_COUNT = 8;

    function automatic integer trace_family(input integer trace_id);
        if (trace_id < TUNING_TRACE_COUNT)
            trace_family = trace_id / 4;
        else
            trace_family = 6 + ((trace_id - TUNING_TRACE_COUNT) / 4);
    endfunction

    function automatic integer trace_variant(input integer trace_id);
        trace_variant = trace_id % 4;
    endfunction

    function automatic integer bounded_occupancy(input integer value);
        if (value < 0)
            bounded_occupancy = 0;
        else if (value > 15)
            bounded_occupancy = 15;
        else
            bounded_occupancy = value;
    endfunction

    function automatic integer trace_occupancy(
        input integer trace_id,
        input integer direction,
        input integer index
    );
        integer family;
        integer variant;
        integer onset;
        integer duration;
        integer level;
        integer elapsed;
        integer rate;
        integer period;
        integer phase;
        begin
            family = trace_family(trace_id);
            variant = trace_variant(trace_id);
            onset = 3 + (variant * 3) + ((trace_id / 2) % 2);
            duration = 1 + (variant % 3);
            level = 12 + (variant % 4);
            elapsed = index - onset;
            rate = 1 + (variant % 2);
            period = 5 + variant;
            phase = (index - (onset + variant)) % period;

            case (family)
                0: begin
                    if (direction == (variant % DIRECTIONS) && elapsed >= 0)
                        trace_occupancy = bounded_occupancy(1 + (elapsed + 1) * rate);
                    else
                        trace_occupancy = 1 + (direction * variant % 3);
                end
                1: begin
                    if (direction == (variant % DIRECTIONS)
                        && elapsed >= 0 && elapsed < duration)
                        trace_occupancy = level;
                    else
                        trace_occupancy = 1 + (variant % 3);
                end
                2: begin
                    if (direction == (variant % DIRECTIONS)
                        && index >= onset && index < onset + 8 + 2 * variant)
                        trace_occupancy = level;
                    else if (direction != (variant % DIRECTIONS)
                        && variant == 2 && index >= onset + 4 && index < onset + 10)
                        trace_occupancy = 12;
                    else
                        trace_occupancy = 2;
                end
                3: begin
                    if (direction == (variant % DIRECTIONS)) begin
                        if (index < onset + 5 + variant)
                            trace_occupancy = level;
                        else
                            trace_occupancy = bounded_occupancy(
                                level - (index - (onset + 5 + variant)) * rate);
                    end else
                        trace_occupancy = 2;
                end
                4: begin
                    if (direction == (variant % DIRECTIONS)
                        && phase >= 0 && phase < duration)
                        trace_occupancy = level;
                    else
                        trace_occupancy = 1 + (variant % 2);
                end
                5: begin
                    if (direction == (variant % DIRECTIONS))
                        trace_occupancy = 7 + (variant % 5);
                    else
                        trace_occupancy = 2 + (variant % 3);
                end
                6: begin
                    if (direction == 0 && index >= onset
                        && index < onset + 7 + variant)
                        trace_occupancy = 12 + (variant % 4);
                    else if (direction == 1 && variant >= 2
                        && index >= onset + 8 && index < onset + 12)
                        trace_occupancy = 12;
                    else
                        trace_occupancy = 1 + direction;
                end
                7: begin
                    if (index >= onset + direction * (4 + variant)
                        && index < onset + direction * (4 + variant)
                            + 6 + (variant % 3))
                        trace_occupancy = 12 + ((variant + direction) % 4);
                    else
                        trace_occupancy = 1 + ((variant + direction) % 3);
                end
                default: trace_occupancy = 1;
            endcase
        end
    endfunction

    function automatic integer trace_traffic(
        input integer trace_id,
        input integer direction,
        input integer index
    );
        integer family;
        integer variant;
        integer onset;
        integer elapsed;
        integer phase;
        integer period;
        begin
            family = trace_family(trace_id);
            variant = trace_variant(trace_id);
            onset = 3 + (variant * 3) + ((trace_id / 2) % 2);
            elapsed = index - onset;
            period = 5 + variant;
            phase = (index - (onset + variant)) % period;
            case (family)
                0: trace_traffic = (direction == (variant % DIRECTIONS)
                    && elapsed >= 0) ? (3 + (variant % 5)) : (variant % 2);
                1: trace_traffic = (direction == (variant % DIRECTIONS)
                    && elapsed >= 0 && elapsed < 1 + (variant % 3))
                    ? (6 + variant * 2) : 0;
                2: trace_traffic = (direction == (variant % DIRECTIONS)
                    && index >= onset && index < onset + 8 + 2 * variant)
                    ? (5 + variant * 2) : 1;
                3: trace_traffic = (direction == (variant % DIRECTIONS)
                    && index < onset + 5 + variant) ? (7 + variant) : 1;
                4: trace_traffic = (direction == (variant % DIRECTIONS)
                    && phase >= 0 && phase < 1 + (variant % 3))
                    ? (7 + variant) : 0;
                5: trace_traffic = (direction == (variant % DIRECTIONS))
                    ? (7 + 2 * variant) : (variant % 3);
                6: trace_traffic = (direction == 0 && index >= onset
                    && index < onset + 7 + variant) ? (4 + variant) : 1;
                7: trace_traffic = (index >= onset + direction * (4 + variant)
                    && index < onset + direction * (4 + variant) + 6 + (variant % 3))
                    ? (5 + variant + direction) : 0;
                default: trace_traffic = 0;
            endcase
            if (trace_traffic < 0)
                trace_traffic = 0;
            else if (trace_traffic > 15)
                trace_traffic = 15;
        end
    endfunction

    function automatic logic trace_history(
        input integer trace_id,
        input integer direction,
        input integer index
    );
        begin
            trace_history = (index > 0)
                && (trace_occupancy(trace_id, direction, index - 1) >= 8);
        end
    endfunction

    function automatic logic trace_is_rising(
        input integer trace_id,
        input integer direction,
        input integer index
    );
        integer previous_occupancy;
        begin
            previous_occupancy = (index == 0)
                ? 0 : trace_occupancy(trace_id, direction, index - 1);
            trace_is_rising =
                trace_occupancy(trace_id, direction, index) > previous_occupancy;
        end
    endfunction

    function automatic integer first_crossing(
        input integer trace_id,
        input integer direction
    );
        integer crossing;
        begin
            crossing = TRACE_LENGTH;
            for (integer index = 0; index < TRACE_LENGTH; index++) begin
                if (crossing == TRACE_LENGTH
                    && trace_occupancy(trace_id, direction, index)
                        >= OCCUPANCY_EVENT_THRESHOLD)
                    crossing = index;
            end
            first_crossing = crossing;
        end
    endfunction

    function automatic logic future_event(
        input integer trace_id,
        input integer direction,
        input integer index
    );
        logic event_seen;
        begin
            event_seen = 1'b0;
            for (integer offset = 1; offset <= HORIZON; offset++) begin
                if (trace_occupancy(trace_id, direction, index + offset)
                    >= OCCUPANCY_EVENT_THRESHOLD)
                    event_seen = 1'b1;
            end
            future_event = event_seen;
        end
    endfunction
endpackage
