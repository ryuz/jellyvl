

// 符号なし整数マルチサイクル除算器
module jellyvl_divider_unsigned_multicycle #(
    parameter int unsigned DIVIDEND_WIDTH  = 32            ,
    parameter int unsigned DIVISOR_WIDTH   = 32            ,
    parameter int unsigned QUOTIENT_WIDTH  = DIVIDEND_WIDTH,
    parameter int unsigned REMAINDER_WIDTH = DIVISOR_WIDTH 
) (
    input logic rst,
    input logic clk,
    input logic cke,

    // input
    input  logic [DIVIDEND_WIDTH-1:0] s_dividend, // 被除数
    input  logic [DIVISOR_WIDTH-1:0]  s_divisor , // 除数
    input  logic                      s_valid   ,
    output logic                      s_ready   ,

    // output
    output logic [QUOTIENT_WIDTH-1:0]  m_quotient ,
    output logic [REMAINDER_WIDTH-1:0] m_remainder,
    output logic                       m_valid    ,
    input  logic                       m_ready
);

    // param
    localparam int unsigned CYCLE       = QUOTIENT_WIDTH;
    localparam int unsigned CYCLE_WIDTH = (($clog2(CYCLE + 1) > 0) ? ( $clog2(CYCLE + 1) ) : ( 1 ));

    // type
    localparam type t_cycle     = logic [CYCLE_WIDTH-1:0];
    localparam type t_dividend  = logic [DIVIDEND_WIDTH-1:0];
    localparam type t_divisor   = logic [DIVISOR_WIDTH-1:0];
    localparam type t_quotient  = logic [QUOTIENT_WIDTH-1:0];
    localparam type t_remainder = logic [REMAINDER_WIDTH-1:0];
    localparam type t_shiftreg  = logic [DIVISOR_WIDTH + QUOTIENT_WIDTH-1:0];

    function automatic t_shiftreg MakeDivisor(
        input t_divisor divisor
    ) ;
        return t_shiftreg'(divisor) << (QUOTIENT_WIDTH - 1);
    endfunction

    logic      busy        ;
    t_cycle    cycle       ;
    t_shiftreg divisor     ;
    t_shiftreg shiftreg    ;
    t_shiftreg shiftreg_sub;

    logic sub_sign;
    always_comb sub_sign = shiftreg_sub[DIVISOR_WIDTH + QUOTIENT_WIDTH - 1];

    t_shiftreg shiftreg_in  ;
    t_shiftreg shiftreg_cmp ;
    t_shiftreg shiftreg_next;
    always_comb shiftreg_in   = t_shiftreg'(s_dividend);
    always_comb shiftreg_cmp  = ((sub_sign) ? ( shiftreg ) : ( shiftreg_sub ));
    always_comb begin
        shiftreg_next    = shiftreg_cmp << 1;
        shiftreg_next[0] = ~sub_sign;
    end

    always_ff @ (posedge clk) begin
        if (rst) begin
            m_valid      <= 1'b0;
            busy         <= 1'b0;
            cycle        <= 'x;
            divisor      <= 'x;
            shiftreg     <= 'x;
            shiftreg_sub <= 'x;
        end else begin
            if ((cke && (!m_valid || m_ready))) begin
                if (busy) begin
                    cycle        <= cycle        - (1);
                    m_valid      <= (cycle == '0);
                    shiftreg_sub <= shiftreg_next - divisor;
                    shiftreg     <= shiftreg_next;
                    if (m_valid) begin
                        busy <= 1'b0;
                    end
                end else begin
                    if (s_valid && s_ready) begin
                        busy         <= 1'b1;
                        cycle        <= t_cycle'((CYCLE - 1));
                        divisor      <= MakeDivisor(s_divisor);
                        shiftreg     <= shiftreg_in;
                        shiftreg_sub <= shiftreg_in - MakeDivisor(s_divisor);
                    end
                end
            end
        end
    end

    always_comb s_ready     = ~busy;
    always_comb m_quotient  = t_quotient'(shiftreg[0+:QUOTIENT_WIDTH]);
    always_comb m_remainder = t_remainder'(shiftreg[QUOTIENT_WIDTH+:DIVISOR_WIDTH]);
endmodule
//# sourceMappingURL=jellyvl_divider_unsigned_multicycle.sv.map
