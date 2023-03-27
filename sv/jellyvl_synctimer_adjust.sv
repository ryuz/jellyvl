
// 調整機構
module jellyvl_synctimer_adjust #(
    parameter int unsigned TIMER_WIDTH     = 32                   , // タイマのbit幅
    parameter int unsigned CYCLE_WIDTH     = 32                   , // 自クロックサイクルカウンタのbit数
    parameter int unsigned ERROR_WIDTH     = 32                   , // 誤差計算時のbit幅
    parameter int unsigned ERROR_Q         = 8                    , // 誤差計算時に追加する固定小数点数bit数
    parameter int unsigned ADJUST_WIDTH    = CYCLE_WIDTH + ERROR_Q, // 補正周期のbit幅
    parameter int unsigned ADJUST_Q        = ERROR_Q              , // 補正周期に追加する固定小数点数bit数
    parameter int unsigned LPF_GAIN_CYCLE  = 6                    , // 自クロックサイクルカウントLPFの更新ゲイン(1/2^N)
    parameter int unsigned LPF_GAIN_PERIOD = 6                    , // 周期補正のLPFの更新ゲイン(1/2^N)
    parameter int unsigned LPF_GAIN_PHASE  = 6                    , // 位相補正のLPFの更新ゲイン(1/2^N)
    parameter bit          DEBUG           = 1'b0                 ,
    parameter bit          SIMULATION      = 1'b0             
) (
    input logic reset,
    input logic clk  ,

    input logic signed [ERROR_WIDTH-1:0] param_adjust_min,
    input logic signed [ERROR_WIDTH-1:0] param_adjust_max,

    input logic [TIMER_WIDTH-1:0] current_time,

    input logic                   correct_override,
    input logic [TIMER_WIDTH-1:0] correct_time    ,
    input logic                   correct_valid   ,

    output logic adjust_sign ,
    output logic adjust_valid,
    input  logic adjust_ready
);

    localparam int unsigned CYCLE_Q = LPF_GAIN_CYCLE;


    // type
    localparam type t_time    = logic [TIMER_WIDTH-1:0];
    localparam type t_count   = logic [CYCLE_WIDTH-1:0];
    localparam type t_cycle   = logic [CYCLE_WIDTH + CYCLE_Q-1:0];
    localparam type t_error   = logic signed [ERROR_WIDTH + ERROR_Q-1:0];
    localparam type t_error_u = logic [ERROR_WIDTH + ERROR_Q-1:0];
    localparam type t_adjust  = logic [ADJUST_WIDTH + ADJUST_Q-1:0];


    // -------------------------------------
    //  一周期の自クロックのサイクル数推定
    // -------------------------------------

    // サイクルカウント
    t_count count_cycle ;
    logic   count_enable;
    logic   count_valid ;
    always_ff @ (posedge clk) begin
        if (reset) begin
            count_cycle  <= 'x;
            count_enable <= 1'b0;
        end else begin
            count_cycle <= count_cycle + (t_count'(1));
            if (correct_valid) begin
                count_cycle  <= t_count'(1);
                count_enable <= 1'b1;
            end
        end
    end
    assign count_valid = correct_valid & count_enable;


    // １周期のサイクル数予測
    t_cycle cycle_observe_t        ; // サイクル数の観測値
    logic   cycle_observe_t_en     ;
    t_cycle cycle_predict_t        ; // サイクル数の観測値
    logic   cycle_predict_t_en     ;
    t_cycle cycle_predict_t_gain   ; // 位相誤差の予測値にゲインを掛けたもの
    logic   cycle_predict_t_gain_en;
    t_cycle cycle_estimate_t       ; // 位相誤差の推定値
    logic   cycle_estimate_t_en    ;
    t_cycle cycle_estimate_t0      ; // １つ前の位相誤差の推定値
    logic   cycle_estimate_t0_en   ;

    assign cycle_predict_t    = cycle_estimate_t0;
    assign cycle_predict_t_en = cycle_estimate_t0_en;

    always_ff @ (posedge clk) begin
        if (reset) begin
            cycle_observe_t         <= 'x;
            cycle_observe_t_en      <= 1'b0;
            cycle_predict_t_gain    <= 'x;
            cycle_predict_t_gain_en <= 1'b0;
            cycle_estimate_t        <= 'x;
            cycle_estimate_t_en     <= 1'b0;
            cycle_estimate_t0       <= 'x;
            cycle_estimate_t0_en    <= 1'b0;
        end else begin
            if (count_valid) begin
                // 観測値ラッチ
                cycle_observe_t    <= t_cycle'(count_cycle) <<< CYCLE_Q;
                cycle_observe_t_en <= count_enable;

                // １つ前の値保存
                cycle_estimate_t0    <= cycle_estimate_t;
                cycle_estimate_t0_en <= cycle_estimate_t_en;
            end

            // LPFをかけて推定値とする
            cycle_predict_t_gain    <= cycle_predict_t - (cycle_predict_t >>> CYCLE_Q);
            cycle_predict_t_gain_en <= cycle_predict_t_en;
            if (cycle_observe_t_en) begin
                if (cycle_predict_t_gain_en) begin
                    cycle_estimate_t <= cycle_predict_t_gain + (cycle_observe_t >>> CYCLE_Q);
                end else begin
                    cycle_estimate_t <= cycle_observe_t; // 初回のみ計測値そのまま
                end
                cycle_estimate_t_en <= cycle_observe_t_en;
            end
        end
    end



    // -------------------------------------
    //  時計の誤差修正
    // -------------------------------------

    // 誤差推定
    t_error         error_observe_x        ; // 位相誤差の観測値
    logic           error_observe_x_en     ;
    t_error         error_predict_x        ; // 位相誤差の予測値
    logic           error_predict_x_en     ;
    t_error         error_predict_x_gain   ; // 位相誤差の予測値にゲインを掛けたもの
    logic           error_predict_x_gain_en;
    t_error         error_estimate_x       ; // 位相誤差の推定値
    logic           error_estimate_x_en    ;
    t_error         error_estimate_x0      ; // １つ前の位相誤差の推定値
    logic           error_estimate_x0_en   ;
    t_error         error_estimate_xx      ;
    logic           error_estimate_xx_en   ;
    t_error         error_observe_v        ; // 周期誤差の観測値
    logic           error_observe_v_en     ;
    t_error         error_predict_v        ; // 位相誤差の予測値
    logic           error_predict_v_en     ;
    t_error         error_predict_v_gain   ; // 周期誤差の予測値にゲインを掛けたもの
    logic           error_predict_v_gain_en;
    t_error         error_estimate_v       ; // 周期誤差の推定値
    logic           error_estimate_v_en    ;
    t_error         error_estimate_v0      ; // １つ前の周期誤差の推定値
    logic           error_estimate_v0_en   ;
    t_error         error_adjust_total     ;
    t_error         error_adjust_value     ; // 制御量(一周期の補正量)
    logic           error_adjust_total_en  ;
    logic   [8-1:0] error_stage            ;
    logic           error_valid            ;

    t_error limit_adjust_min;
    t_error limit_adjust_max;
    assign limit_adjust_min = t_error'(param_adjust_min) <<< ERROR_Q;
    assign limit_adjust_max = t_error'(param_adjust_max) <<< ERROR_Q;

    assign error_predict_v    = error_estimate_v0; // 周期予測はひとつ前の推定値と同じ
    assign error_predict_v_en = error_estimate_v0_en;

    t_time current_error;
    assign current_error = correct_time - current_time;

    always_ff @ (posedge clk) begin
        if (reset) begin
            error_observe_x         <= 'x;
            error_observe_x_en      <= 1'b0;
            error_predict_x         <= 'x;
            error_predict_x_en      <= 1'b0;
            error_predict_x_gain    <= 'x;
            error_predict_x_gain_en <= 1'b0;
            error_estimate_x        <= 'x;
            error_estimate_x_en     <= 1'b0;
            error_estimate_x0       <= 'x;
            error_estimate_x0_en    <= 1'b0;
            error_estimate_xx       <= 'x;
            error_estimate_xx_en    <= 1'b0;
            error_observe_v         <= 'x;
            error_observe_v_en      <= 1'b0;
            error_predict_v_gain    <= 'x;
            error_predict_v_gain_en <= 1'b0;
            error_estimate_v        <= 'x;
            error_estimate_v_en     <= 1'b0;
            error_estimate_v0       <= 'x;
            error_estimate_v0_en    <= 1'b0;
            error_adjust_total      <= 'x;
            error_adjust_total_en   <= 1'b0;
            error_adjust_value      <= '0;
            error_stage             <= '0;
            error_valid             <= 1'b0;
        end else begin
            error_stage <= error_stage << (1);

            if (correct_valid) begin
                error_stage[0] <= 1'b1;

                if (correct_override) begin
                    // 時刻上書き時
                    error_observe_x         <= '0;
                    error_observe_x_en      <= 1'b1;
                    error_predict_x         <= 'x;
                    error_predict_x_en      <= 1'b0;
                    error_predict_x_gain    <= 'x;
                    error_predict_x_gain_en <= 1'b0;
                    error_estimate_x        <= 'x;
                    error_estimate_x_en     <= 1'b0;
                    error_estimate_x0       <= 'x;
                    error_estimate_x0_en    <= 1'b0;
                    error_estimate_xx       <= 'x;
                    error_estimate_xx_en    <= 1'b0;
                    error_observe_v         <= 'x;
                    error_observe_v_en      <= 1'b0;
                    error_predict_v_gain    <= 'x;
                    error_predict_v_gain_en <= 1'b0;
                    error_estimate_v        <= 'x;
                    error_estimate_v_en     <= 1'b0;
                    error_estimate_v0       <= 'x;
                    error_estimate_v0_en    <= 1'b0;
                    error_adjust_total      <= 'x;
                    error_adjust_total_en   <= 1'b0;
                    error_adjust_value      <= '0;
                end else begin
                    // 観測値ラッチ
                    error_observe_x    <= t_error'(current_error) <<< ERROR_Q;
                    error_observe_x_en <= 1'b1;

                    // 1つ前の予測保存
                    error_estimate_x0    <= error_estimate_x;
                    error_estimate_x0_en <= error_estimate_x_en;

                    error_estimate_v0    <= error_estimate_v;
                    error_estimate_v0_en <= error_estimate_v_en;
                end
            end

            if (error_stage[0]) begin
                error_estimate_xx    <= error_estimate_x0 - error_adjust_value;
                error_estimate_xx_en <= error_estimate_x0_en;
            end

            if (error_stage[1]) begin
                // 位相ずれ予測
                //              error_predict_x    = error_estimate_x0 + error_estimate_v0 - error_adjust_value;
                error_predict_x    <= error_estimate_xx + error_estimate_v0;
                error_predict_x_en <= error_estimate_xx_en & error_estimate_v0_en;
            end

            if (error_stage[2]) begin
                // LPF用ゲイン計算
                error_predict_x_gain    <= error_predict_x - (error_predict_x >>> LPF_GAIN_PHASE);
                error_predict_x_gain_en <= error_predict_x_en;
            end

            if (error_stage[3]) begin
                // 位相ずれ推定
                if (error_observe_x_en) begin
                    if (error_predict_x_gain_en) begin
                        error_estimate_x <= error_predict_x_gain + (error_observe_x >>> LPF_GAIN_PHASE);
                    end else begin
                        error_estimate_x <= error_observe_x;
                    end
                    error_estimate_x_en <= 1'b1;
                end
            end

            if (error_stage[4]) begin
                // 周期ずれ予測
                error_observe_v    <= error_estimate_x - error_estimate_xx; // (error_estimate_x0 - error_adjust_value);
                error_observe_v_en <= error_estimate_x_en && error_estimate_xx_en;

                // LPF用ゲイン計算
                error_predict_v_gain    <= error_predict_v - (error_predict_v >>> LPF_GAIN_PERIOD);
                error_predict_v_gain_en <= error_predict_v_en;
            end

            if (error_stage[5]) begin
                // 周期ずれ推定
                if (error_observe_v_en) begin
                    if (error_predict_v_gain_en) begin
                        error_estimate_v <= error_predict_v_gain + (error_observe_v >>> LPF_GAIN_PHASE);
                    end else begin
                        error_estimate_v <= error_observe_v;
                    end
                    error_estimate_v_en <= 1'b1;
                end
            end

            if (error_stage[6]) begin
                // 制御量合計
                error_adjust_total    <= error_estimate_x + error_estimate_v;
                error_adjust_total_en <= error_estimate_x_en && error_estimate_v_en;
            end

            error_valid <= 1'b0;
            if (error_stage[7]) begin
                // limitter
                if (error_adjust_total_en) begin
                    error_adjust_value <= error_adjust_total;
                    if (error_adjust_total < limit_adjust_min) begin
                        error_adjust_value <= limit_adjust_min;
                    end
                    if (error_adjust_total > limit_adjust_max) begin
                        error_adjust_value <= limit_adjust_max;
                    end
                    error_valid <= 1'b1;
                end
            end
        end
    end



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
            if (error_valid) begin
                div_calc_sign  <= error_adjust_value < 0;
                div_calc_zero  <= error_adjust_value == 0;
                div_calc_error <= ((error_adjust_value < 0) ? (
                    t_error_u'((-error_adjust_value))
                ) : (
                    t_error_u'(error_adjust_value)
                ));
                div_calc_cycle  <= cycle_estimate_t;
                div_calc_enable <= 1'b1;
            end
            div_calc_valid <= error_valid;
        end
    end


    // divider
    localparam type t_cycle_q = logic [CYCLE_WIDTH + ERROR_Q + ADJUST_Q-1:0];

    function automatic t_cycle_q CycleToError(
        input t_cycle cycle
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
                if (adj_param_valid) begin
                    adj_calc_zero   <= adj_param_zero;
                    adj_calc_sign   <= adj_param_sign;
                    adj_calc_period <= adj_param_period;
                    adj_calc_count  <= '0;
                end else begin
                    adj_calc_count <= adj_calc_next;
                end
                adj_calc_valid <= 1'b0;
            end
        end
    end

    assign adj_param_ready = adj_calc_valid;


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
        logic [TIMER_WIDTH-1:0] dbg_current_time;
        (* mark_debug="true" *)
        logic dbg_correct_override;
        (* mark_debug="true" *)
        logic [TIMER_WIDTH-1:0] dbg_correct_time;
        (* mark_debug="true" *)
        logic dbg_correct_valid;
        (* mark_debug="true" *)
        t_error dbg_error_adjust_value;
        (* mark_debug="true" *)
        logic signed [TIMER_WIDTH-1:0] dbg_diff_time;
        (* mark_debug="true" *)
        logic [TIMER_WIDTH-1:0] dbg_diff_time_abs;
        (* mark_debug="true" *)
        t_error dbg_error_estimate_x;
        (* mark_debug="true" *)
        t_error dbg_error_estimate_v;
        (* mark_debug="true" *)
        t_error dbg_error_estimate_x0;
        (* mark_debug="true" *)
        t_error dbg_error_estimate_v0;
        (* mark_debug="true" *)
        t_cycle dbg_cycle_observe_t;
        (* mark_debug="true" *)
        t_cycle dbg_cycle_predict_t;
        (* mark_debug="true" *)
        t_cycle dbg_cycle_estimate_t;
        (* mark_debug="true" *)
        t_cycle dbg_cycle_estimate_t0;

        logic signed [TIMER_WIDTH-1:0] dbg_diff_time_tmp;
        assign dbg_diff_time_tmp = correct_time - current_time;

        always_ff @ (posedge clk) begin
            dbg_current_time       <= current_time;
            dbg_correct_override   <= correct_override;
            dbg_correct_time       <= correct_time;
            dbg_correct_valid      <= correct_valid;
            dbg_error_adjust_value <= error_adjust_value;
            dbg_diff_time          <= dbg_diff_time_tmp;
            dbg_diff_time_abs      <= ((dbg_diff_time_tmp >= 0) ? (
                dbg_diff_time_tmp
            ) : (
                -dbg_diff_time_tmp
            ));
            dbg_error_estimate_x   <= error_estimate_x;
            dbg_error_estimate_v   <= error_estimate_v;
            dbg_error_estimate_x0  <= error_estimate_x0;
            dbg_error_estimate_v0  <= error_estimate_v0;
            dbg_cycle_observe_t    <= cycle_observe_t;
            dbg_cycle_predict_t    <= cycle_predict_t;
            dbg_cycle_estimate_t   <= cycle_estimate_t;
            dbg_cycle_estimate_t0  <= cycle_estimate_t0;

        end
    end

    if (SIMULATION) begin :sim_monitor
        real sim_monitor_cycle_estimate_t    ;
        real sim_monitor_error_observe_x     ; // 位相誤差の観測値
        real sim_monitor_error_predict_x     ; // 位相誤差の予測値
        real sim_monitor_error_predict_x_gain; // 位相誤差の予測値にゲインを掛けたもの
        real sim_monitor_error_estimate_x    ; // 位相誤差の推定値
        real sim_monitor_error_estimate_x0   ; // １つ前の位相誤差の推定値
        real sim_monitor_error_observe_v     ; // 周期誤差の観測値
        real sim_monitor_error_predict_v     ; // 位相誤差の予測値
        real sim_monitor_error_predict_v_gain; // 周期誤差の予測値にゲインを掛けたもの
        real sim_monitor_error_estimate_v    ; // 周期誤差の推定値
        real sim_monitor_error_estimate_v0   ; // １つ前の周期誤差の推定値
        real sim_monitor_error_adjust_value  ;
        real sim_monitor_adj_param_period    ;
        real sim_monitor_debug_count         ;

        assign sim_monitor_cycle_estimate_t     = $itor(cycle_estimate_t) / $itor(2 ** CYCLE_Q);
        assign sim_monitor_error_observe_x      = $itor(error_observe_x) / $itor(2 ** ERROR_Q);
        assign sim_monitor_error_predict_x      = $itor(error_predict_x) / $itor(2 ** ERROR_Q);
        assign sim_monitor_error_predict_x_gain = $itor(error_predict_x_gain) / $itor(2 ** ERROR_Q);
        assign sim_monitor_error_estimate_x     = $itor(error_estimate_x) / $itor(2 ** ERROR_Q);
        assign sim_monitor_error_estimate_x0    = $itor(error_estimate_x0) / $itor(2 ** ERROR_Q);
        assign sim_monitor_error_observe_v      = $itor(error_observe_v) / $itor(2 ** ERROR_Q);
        assign sim_monitor_error_predict_v      = $itor(error_predict_v) / $itor(2 ** ERROR_Q);
        assign sim_monitor_error_predict_v_gain = $itor(error_predict_v_gain) / $itor(2 ** ERROR_Q);
        assign sim_monitor_error_estimate_v     = $itor(error_estimate_v) / $itor(2 ** ERROR_Q);
        assign sim_monitor_error_estimate_v0    = $itor(error_estimate_v0) / $itor(2 ** ERROR_Q);
        assign sim_monitor_error_adjust_value   = $itor(error_adjust_value) / $itor(2 ** ERROR_Q);
        assign sim_monitor_adj_param_period     = $itor(adj_param_period) / $itor(2 ** ADJUST_Q);
        assign sim_monitor_debug_count          = sim_monitor_cycle_estimate_t / sim_monitor_adj_param_period;
    end

endmodule
