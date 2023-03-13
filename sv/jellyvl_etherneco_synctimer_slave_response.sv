
// リクエストの処理
module jellyvl_etherneco_synctimer_slave_response (
    input logic reset,
    input logic clk  ,

    input logic [8-1:0]  node_id   ,
    input logic [32-1:0] delay_time,

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

    logic local_reset;
    assign local_reset = reset || rx_error;

    localparam type t_count = logic [16-1:0];

    logic   busy    ;
    t_count count   ;
    t_count position;
    assign position = t_count'(node_id) * 4 + 8;

    always_ff @ (posedge clk) begin
        if (local_reset) begin
            busy  <= 1'b0;
            count <= '0;

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
                        m_valid <= s_valid;
                    end
                end else begin
                    if (count == position + t_count'(0)) begin
                        m_data <= delay_time[0 * 8+:8];
                    end
                    if (count == position + t_count'(1)) begin
                        m_data <= delay_time[1 * 8+:8];
                    end
                    if (count == position + t_count'(2)) begin
                        m_data <= delay_time[2 * 8+:8];
                    end
                    if (count == position + t_count'(3)) begin
                        m_data <= delay_time[3 * 8+:8];
                    end
                    if (s_last) begin
                        busy <= 1'b0;
                    end
                end
            end
            if (rx_start || rx_end || rx_error) begin
                busy    <= 1'b0;
                m_valid <= 1'b0;
            end
        end
    end
endmodule
