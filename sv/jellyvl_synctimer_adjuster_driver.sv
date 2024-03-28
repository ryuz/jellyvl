
// 調整パルスドライブ
module jellyvl_synctimer_adjuster_driver #(
    parameter int unsigned CYCLE_WIDTH  = 32                   , // 自クロックサイクルカウンタのbit数
    parameter int unsigned CYCLE_Q      = 8                    , // 自クロックサイクルカウンタに追加する固定小数点数bit数
    parameter int unsigned ERROR_WIDTH  = 32                   , // 誤差計算時のbit幅
    parameter int unsigned ERROR_Q      = 8                    , // 誤差計算時に追加する固定小数点数bit数
    parameter int unsigned ADJUST_WIDTH = CYCLE_WIDTH + ERROR_Q, // 補正周期のbit幅
    parameter int unsigned ADJUST_Q     = ERROR_Q              , // 補正周期に追加する固定小数点数bit数
    parameter bit          DEBUG        = 1'b0                 ,
    parameter bit          SIMULATION   = 1'b0             
) (
    input logic reset,
    input logic clk  ,

    input logic signed [ERROR_WIDTH + ERROR_Q-1:0] request_value,
    input logic        [CYCLE_WIDTH + CYCLE_Q-1:0] request_cycle,
    input logic                                    request_valid,

    output logic adjust_sign ,
    output logic adjust_valid,
    input  logic adjust_ready
);


    // type
    localparam type t_error   = logic signed [ERROR_WIDTH + ERROR_Q-1:0];
    localparam type t_error_u = logic [ERROR_WIDTH + ERROR_Q-1:0];
    localparam type t_count   = logic [CYCLE_WIDTH-1:0];
    localparam type t_cycle   = logic [CYCLE_WIDTH + CYCLE_Q-1:0];
    localparam type t_adjust  = logic [ADJUST_WIDTH + ADJUST_Q-1:0];


    // -------------------------------------
    //  調整信号の間隔計算
    // -------------------------------------

    logic     div_calc_sign  ;
    logic     div_calc_zero  ;
    t_error_u div_calc_error ;
    t_cycle   div_calc_cycle ;
    logic     div_calc_enable;
    logic     div_calc_valid ;

    always_ff @ (posedge clk) begin
        if (reset) begin
            div_calc_sign   <= 'x;
            div_calc_zero   <= 'x;
            div_calc_error  <= 'x;
            div_calc_cycle  <= 'x;
            div_calc_enable <= 1'b0;
            div_calc_valid  <= 1'b0;
        end else begin
            if (request_valid) begin
                div_calc_sign  <= request_value < 0;
                div_calc_zero  <= request_value == 0;
                div_calc_error <= ((request_value < 0) ? (
                    t_error_u'((-request_value))
                ) : (
                    t_error_u'(request_value)
                ));
                div_calc_cycle  <= request_cycle;
                div_calc_enable <= 1'b1;
            end
            div_calc_valid <= request_valid;
        end
    end


    // divider
    localparam type t_cycle_q = logic [CYCLE_WIDTH + ERROR_Q + ADJUST_Q-1:0];

    function automatic t_cycle_q CycleToError(
        input t_cycle   cycle
    ) ;
        if (ERROR_Q + ADJUST_Q > CYCLE_Q) begin
            return t_cycle_q'(cycle) << (ERROR_Q + ADJUST_Q - CYCLE_Q);
        end else begin
            return t_cycle_q'(cycle) >> (CYCLE_Q - ERROR_Q - ADJUST_Q);
        end
    endfunction

    t_adjust div_quotient ;
    t_error  div_remainder;
    logic    div_valid    ;

    logic tmp_ready;
    jellyvl_divider_unsigned_multicycle #(
        .DIVIDEND_WIDTH (CYCLE_WIDTH + ERROR_Q + ADJUST_Q),
        .DIVISOR_WIDTH  (ERROR_WIDTH + ERROR_Q           ),
        .QUOTIENT_WIDTH (ADJUST_WIDTH + ADJUST_Q         )
    ) i_divider_unsigned_multicycle (
        .reset (reset),
        .clk   (clk  ),
        .cke   (1'b1 ),
        .
        s_dividend (CycleToError(div_calc_cycle)),
        .s_divisor  (div_calc_error              ),
        .s_valid    (div_calc_valid              ),
        .s_ready    (tmp_ready                   ),
        .
        m_quotient  (div_quotient ),
        .m_remainder (div_remainder),
        .m_valid     (div_valid    ),
        .m_ready     (1'b1         )
    );


    // adjust parameter
    localparam t_adjust ADJ_STEP = t_adjust'((1 << ADJUST_Q));

    logic    adj_param_zero  ;
    logic    adj_param_sign  ;
    t_adjust adj_param_period;
    logic    adj_param_valid ;
    logic    adj_param_ready ;

    always_ff @ (posedge clk) begin
        if (reset) begin
            adj_param_zero   <= 1'b1;
            adj_param_sign   <= 1'bx;
            adj_param_period <= 'x;
            adj_param_valid  <= 1'b0;
        end else begin
            if (adj_param_ready) begin
                adj_param_valid <= 1'b0;
            end

            if (div_valid) begin
                if (div_calc_zero) begin
                    adj_param_zero   <= 1'b1;
                    adj_param_sign   <= 1'b0;
                    adj_param_period <= '0;
                    adj_param_valid  <= !adj_param_zero; // 変化があれば発行
                end else begin
                    adj_param_zero   <= div_calc_zero;
                    adj_param_sign   <= div_calc_sign;
                    adj_param_period <= div_quotient - ADJ_STEP;
                    adj_param_valid  <= adj_param_zero || ((div_quotient - ADJ_STEP) != adj_param_period);
                end
            end
        end
    end

    // adjuster
    logic    adj_calc_zero  ;
    logic    adj_calc_sign  ;
    t_adjust adj_calc_period;
    t_adjust adj_calc_count ;
    t_adjust adj_calc_next  ;
    logic    adj_calc_valid ;

    always_ff @ (posedge clk) begin
        if (reset) begin
            adj_calc_zero   <= 1'b1;
            adj_calc_sign   <= 'x;
            adj_calc_period <= '0;
            adj_calc_count  <= 'x;
            adj_calc_next   <= 'x;
            adj_calc_valid  <= 1'b0;
        end else begin

            // adj_param_valid は連続で来ない、period は2以上の前提で事前計算
            adj_calc_count <= adj_calc_count + (t_adjust'((1 << ADJUST_Q)));
            adj_calc_next  <=  adj_calc_count - adj_calc_period;
            adj_calc_valid <=  adj_calc_count >= adj_calc_period || adj_calc_zero;

            if (adj_calc_valid) begin
                adj_calc_count <= adj_calc_next;
                adj_calc_valid <= 1'b0;
            end

            if (adj_param_valid) begin
                adj_calc_zero   <= adj_param_zero;
                adj_calc_sign   <= adj_param_sign;
                adj_calc_period <= adj_param_period;
                adj_calc_count  <= '0;
                adj_calc_valid  <= 1'b0;
            end
        end
    end

    always_comb adj_param_ready = 1'b1; // adj_calc_valid;


    // output
    always_ff @ (posedge clk) begin
        if (reset) begin
            adjust_sign  <= 'x;
            adjust_valid <= 1'b0;
        end else begin
            if (adjust_ready) begin
                adjust_valid <= 1'b0;
            end

            if (adj_calc_valid) begin
                adjust_sign  <= adj_calc_sign;
                adjust_valid <= ~adj_calc_zero;
            end
        end
    end

    if (DEBUG) begin :debug_monitor
        (* mark_debug="true" *)
        logic [32-1:0] dbg_counter;
        (* mark_debug="true" *)
        logic signed [16-1:0] dbg_adj_sum;
        (* mark_debug="true" *)
        logic dbg_adjust_sign;
        (* mark_debug="true" *)
        logic dbg_adjust_valid;
        (* mark_debug="true" *)
        logic dbg_adjust_ready;

        always_ff @ (posedge clk) begin
            dbg_counter <= dbg_counter + 1;

            if (request_valid) begin
                dbg_adj_sum <= '0;
            end else begin
                if (adjust_valid) begin
                    if (adjust_sign) begin
                        dbg_adj_sum <= dbg_adj_sum - (16'd1);
                    end else begin
                        dbg_adj_sum <= dbg_adj_sum + (16'd1);
                    end
                end
            end

            dbg_adjust_sign  <= adjust_sign;
            dbg_adjust_valid <= adjust_valid;
            dbg_adjust_ready <= adjust_ready;
        end
    end

    if (SIMULATION) begin :sim_monitor
        real sim_monitor_request_value;
        real sim_monitor_request_cycle;

        always_comb sim_monitor_request_value = $itor(request_value) / $itor(2 ** ERROR_Q);
        always_comb sim_monitor_request_cycle = $itor(request_cycle) / $itor(2 ** CYCLE_Q);
    end
endmodule
