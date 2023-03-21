module jellyvl_synctimer_core #(
    parameter int unsigned TIMER_WIDTH         = 64                             , // タイマのbit幅
    parameter int unsigned NUMERATOR           = 10                             , // クロック周期の分子
    parameter int unsigned DENOMINATOR         = 3                              , // クロック周期の分母
    parameter int unsigned ADJ_COUNTER_WIDTH   = 32                             , // 自クロックで経過時間カウンタのbit数
    parameter int unsigned ADJ_CALC_WIDTH      = 32                             , // タイマのうち計算に使う部分
    parameter int unsigned ADJ_ERROR_WIDTH     = 32                             , // 誤差計算時のbit幅
    parameter int unsigned ADJ_ERROR_Q         = 8                              , // 誤差計算時に追加する固定小数点数bit数
    parameter int unsigned ADJ_ADJUST_WIDTH    = ADJ_COUNTER_WIDTH + ADJ_ERROR_Q, // 補正周期のbit幅
    parameter int unsigned ADJ_ADJUST_Q        = ADJ_ERROR_Q                    , // 補正周期に追加する固定小数点数bit数
    parameter int unsigned ADJ_PERIOD_WIDTH    = ADJ_ERROR_WIDTH                , // 周期補正に使うbit数
    parameter int unsigned ADJ_PHASE_WIDTH     = ADJ_ERROR_WIDTH                , // 位相補正に使うbit数
    parameter int unsigned ADJ_PERIOD_LPF_GAIN = 4                              , // 周期補正のLPFの更新ゲイン(1/2^N)
    parameter int unsigned ADJ_PHASE_LPF_GAIN  = 4                               // 位相補正のLPFの更新ゲイン(1/2^N)
) (
    input logic reset,
    input logic clk  ,

    input logic signed [ADJ_PHASE_WIDTH-1:0] adj_param_phase_min,
    input logic signed [ADJ_PHASE_WIDTH-1:0] adj_param_phase_max,

    input logic [TIMER_WIDTH-1:0] set_time ,
    input logic                   set_valid,

    output logic [TIMER_WIDTH-1:0] current_time,

    input logic                   correct_override,
    input logic [TIMER_WIDTH-1:0] correct_time    ,
    input logic                   correct_valid   

);

    logic adjust_sign ;
    logic adjust_valid;
    logic adjust_ready;

    // タイマ
    jellyvl_synctimer_timer #(
        .NUMERATOR   (NUMERATOR  ),
        .DENOMINATOR (DENOMINATOR),
        .TIMER_WIDTH (TIMER_WIDTH)
    ) u_synctimer_timer (
        .reset (reset),
        .clk   (clk  ),
        .
        set_time (((set_valid) ? (
            set_time
        ) : (
            correct_time
        ))),
        .set_valid (set_valid | (correct_valid & correct_override)),
        .
        adjust_sign  (adjust_sign ),
        .adjust_valid (adjust_valid),
        .adjust_ready (adjust_ready),
        .
        current_time (current_time)
    );

    // 補正ユニット
    jellyvl_synctimer_adjust #(
        .TIMER_WIDTH     (TIMER_WIDTH        ),
        .COUNTER_WIDTH   (ADJ_COUNTER_WIDTH  ),
        .CALC_WIDTH      (ADJ_CALC_WIDTH     ),
        .ERROR_WIDTH     (ADJ_ERROR_WIDTH    ),
        .ERROR_Q         (ADJ_ERROR_Q        ),
        .ADJUST_WIDTH    (ADJ_ADJUST_WIDTH   ),
        .ADJUST_Q        (ADJ_ADJUST_Q       ),
        .PERIOD_WIDTH    (ADJ_PERIOD_WIDTH   ),
        .PHASE_WIDTH     (ADJ_PHASE_WIDTH    ),
        .PERIOD_LPF_GAIN (ADJ_PERIOD_LPF_GAIN),
        .PHASE_LPF_GAIN  (ADJ_PHASE_LPF_GAIN )
    ) u_synctimer_adjust (
        .reset (reset),
        .clk   (clk  ),
        .
        param_phase_min (adj_param_phase_min),
        .param_phase_max (adj_param_phase_max),
        .
        local_time (current_time),
        .
        correct_override (correct_override),
        .correct_time     (correct_time    ),
        .correct_valid    (correct_valid   ),
        .
        adjust_sign  (adjust_sign ),
        .adjust_valid (adjust_valid),
        .adjust_ready (adjust_ready)
    );

endmodule
