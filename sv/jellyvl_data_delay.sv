module jellyvl_data_delay #(
    parameter type         t_data    = logic [8-1:0],
    parameter int unsigned LATENCY   = 1            ,
    parameter t_data       INIT_DATA = 'x       
) (
    input var logic rst,
    input var logic clk,
    input var logic cke,

    input  var t_data s_data ,
    input  var logic  s_valid,
    output var logic  s_ready,

    output var t_data m_data ,
    output var logic  m_valid,
    input  var logic  m_ready
);

    if (LATENCY == 0) begin :bypass
        always_comb s_ready = m_ready;
        always_comb m_data  = s_data;
        always_comb m_valid = s_valid;
    end else begin :delay

        always_comb s_ready = !m_valid || m_ready;

        t_data buf_data  [0:LATENCY-1];
        logic  buf_valid [0:LATENCY-1];
        always_ff @ (posedge clk) begin
            if (rst) begin
                for (int unsigned i = 0; i < LATENCY; i++) begin
                    buf_data[i]  <= INIT_DATA;
                    buf_valid[i] <= 1'b0;
                end
            end else if (cke && s_ready) begin
                buf_data[0]  <= s_data;
                buf_valid[0] <= s_valid;
                for (int unsigned i = 1; i < LATENCY; i++) begin
                    buf_data[i]  <= buf_data[i - 1];
                    buf_valid[i] <= buf_valid[i - 1];
                end
            end
        end

        always_comb m_valid = buf_valid[LATENCY - 1];
        always_comb m_data  = buf_data[LATENCY - 1];
    end
endmodule
//# sourceMappingURL=jellyvl_data_delay.sv.map
