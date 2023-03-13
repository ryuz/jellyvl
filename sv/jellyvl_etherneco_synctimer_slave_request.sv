
// リクエストの処理
module jellyvl_etherneco_synctimer_slave_request (
    input logic reset,
    input logic clk  ,

    output logic          correct_override,
    output logic [64-1:0] correct_time    ,
    output logic          correct_valid   ,

    input logic rx_start,
    input logic rx_error,
    input logic rx_end  ,

    input logic         s_first,
    input logic         s_last ,
    input logic [8-1:0] s_data ,
    input logic         s_valid,

    output logic         m_first,
    output logic         m_last ,
    output logic [8-1:0] m_data ,
    output logic         m_valid
);

    localparam type t_time = logic [64-1:0];

    logic local_reset;
    assign local_reset = reset || rx_error;

    localparam type t_count = logic [16-1:0];

    logic            busy     ;
    t_count          count    ;
    logic   [8-1:0]  rx_cmd   ;
    t_time           rx_time  ;
    logic   [16-1:0] rx_offset;

    always_ff @ (posedge clk) begin
        if (local_reset) begin
            busy      <= 1'b0;
            count     <= '0;
            rx_cmd    <= 'x;
            rx_time   <= 'x;
            rx_offset <= 'x;

            m_first <= 'x;
            m_last  <= 'x;
            m_data  <= 'x;
            m_valid <= 1'b0;
        end else begin
            m_first <= s_first;
            m_last  <= s_last;
            m_data  <= s_data;
            m_valid <= s_valid & busy;

            if (s_valid) begin
                count <= count + 1'b1;

                if (!busy) begin
                    m_valid <= 1'b0;
                    if (s_first) begin
                        busy    <= 1'b1;
                        count   <= '0;
                        rx_cmd  <= s_data;
                        m_data  <= s_data + 1;
                        m_valid <= 1'b1;
                    end
                end else begin
                    case (int'(count))
                        0: begin
                            rx_time[0 * 8+:8] <= s_data;
                        end
                        1: begin
                            rx_time[1 * 8+:8] <= s_data;
                        end
                        2: begin
                            rx_time[2 * 8+:8] <= s_data;
                        end
                        3: begin
                            rx_time[3 * 8+:8] <= s_data;
                        end
                        4: begin
                            rx_time[4 * 8+:8] <= s_data;
                        end
                        5: begin
                            rx_time[5 * 8+:8] <= s_data;
                        end
                        6: begin
                            rx_time[6 * 8+:8] <= s_data;
                        end
                        7: begin
                            rx_time[7 * 8+:8] <= s_data;
                        end
                        8: begin
                            rx_offset[0 * 8+:8] <= s_data;
                        end
                        9: begin
                            rx_offset[1 * 8+:8] <= s_data;
                        end
                        default: begin
                            busy <= 1'b0;
                        end
                    endcase
                    if (s_last) begin
                        busy <= 1'b0;
                    end
                end
            end
            if (rx_start || rx_end || rx_error) begin
                busy <= 1'b0;
            end
        end
    end

    always_ff @ (posedge clk) begin
        if (reset) begin
            correct_override <= 1'bx;
            correct_time     <= 'x;
            correct_valid    <= 1'b0;
        end else begin
            correct_override <= 1'bx;
            correct_time     <= rx_time + t_time'(rx_offset);
            correct_valid    <= 1'b0;

            if (rx_end) begin
                if (rx_cmd[0]) begin
                    correct_override <= 1'b1;
                    correct_valid    <= 1'b1;
                end else begin
                    correct_override <= 1'b0;
                    correct_valid    <= 1'b1;
                end
            end
        end
    end

endmodule
