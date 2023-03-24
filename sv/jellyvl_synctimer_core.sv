module jellyvl_synctimer_core #(
    parameter int unsigned TIMER_WIDTH         = 64                             , // タイマのbit幅
    parameter int unsigned NUMERATOR           = 10                             , // クロック周期の分子
    parameter int unsigned DENOMINATOR         = 3                              , // クロック周期の分母
    parameter int unsigned ADJ_LIMIT_WIDTH     = TIMER_WIDTH                    , // 補正限界のbit幅
    parameter int unsigned ADJ_COUNTER_WIDTH   = 32                             , // 自クロックで経過時間カウンタのbit数
    parameter int unsigned ADJ_CALC_WIDTH      = 32                             , // タイマのうち計算に使う部分
    parameter int unsigned ADJ_ERROR_WIDTH     = 32                             , // 誤差計算時のbit幅
    parameter int unsigned ADJ_ERROR_Q         = 8                              , // 誤差計算時に追加する固定小数点数bit数
    parameter int unsigned ADJ_ADJUST_WIDTH    = ADJ_COUNTER_WIDTH + ADJ_ERROR_Q, // 補正周期のbit幅
    parameter int unsigned ADJ_ADJUST_Q        = ADJ_ERROR_Q                    , // 補正周期に追加する固定小数点数bit数
    parameter int unsigned ADJ_PERIOD_WIDTH    = ADJ_ERROR_WIDTH                , // 周期補正に使うbit数
    parameter int unsigned ADJ_PHASE_WIDTH     = ADJ_ERROR_WIDTH                , // 位相補正に使うbit数
    parameter int unsigned ADJ_PERIOD_LPF_GAIN = 4                              , // 周期補正のLPFの更新ゲイン(1/2^N)
    parameter int unsigned ADJ_PHASE_LPF_GAIN  = 4                              , // 位相補正のLPFの更新ゲイン(1/2^N)
    parameter bit          DEBUG               = 1'b0                           ,
    parameter bit          SIMULATION          = 1'b0                       
) (
    input logic reset,
    input logic clk  ,

    input logic signed [ADJ_LIMIT_WIDTH-1:0]  adj_param_limit_min ,
    input logic signed [ADJ_LIMIT_WIDTH-1:0]  adj_param_limit_max ,
    input logic signed [ADJ_PHASE_WIDTH-1:0]  adj_param_phase_min ,
    input logic signed [ADJ_PHASE_WIDTH-1:0]  adj_param_phase_max ,
    input logic signed [ADJ_PERIOD_WIDTH-1:0] adj_param_period_min,
    input logic signed [ADJ_PERIOD_WIDTH-1:0] adj_param_period_max,

    input logic [TIMER_WIDTH-1:0] set_time ,
    input logic                   set_valid,

    output logic [TIMER_WIDTH-1:0] current_time,

    input logic                   correct_override,
    input logic [TIMER_WIDTH-1:0] correct_time    ,
    input logic                   correct_valid   

);

    // 補正ユニット
    logic override_request;
    assign override_request = 1'b0;

    logic adjust_sign ;
    logic adjust_valid;
    logic adjust_ready;

    jellyvl_synctimer_adjust #(
        .TIMER_WIDTH (TIMER_WIDTH),
        //        LIMIT_WIDTH    : ADJ_LIMIT_WIDTH    ,
        //        COUNTER_WIDTH  : ADJ_COUNTER_WIDTH  ,
        //        CALC_WIDTH     : ADJ_CALC_WIDTH     ,
        //        ERROR_WIDTH    : ADJ_ERROR_WIDTH    ,
        //        ERROR_Q        : ADJ_ERROR_Q        ,
        //        ADJUST_WIDTH   : ADJ_ADJUST_WIDTH   ,
        //        ADJUST_Q       : ADJ_ADJUST_Q       ,
        //        PERIOD_WIDTH   : ADJ_PERIOD_WIDTH   ,
        //        PHASE_WIDTH    : ADJ_PHASE_WIDTH    ,
        //        PERIOD_LPF_GAIN: ADJ_PERIOD_LPF_GAIN,
        //        PHASE_LPF_GAIN : ADJ_PHASE_LPF_GAIN ,
        .DEBUG      (DEBUG     ),
        .SIMULATION (SIMULATION)
    ) u_synctimer_adjust (
        .reset (reset),
        .clk   (clk  ),
        .
        current_time (current_time),

        //        param_cycle_min :  -32'd100,
        //       param_cycle_max :  +32'd100,
        .param_adjust_min (-32'd100),
        .param_adjust_max (+32'd100),
        .
        correct_override (correct_override),
        .correct_time     (correct_time    ),
        .correct_valid    (correct_valid   ),
        .
        adjust_sign  (adjust_sign ),
        .adjust_valid (adjust_valid),
        .adjust_ready (adjust_ready)
    );


    // タイマユニット
    logic [TIMER_WIDTH-1:0] timer_set_time ;
    logic                   timer_set_valid;

    jellyvl_synctimer_timer #(
        .NUMERATOR   (NUMERATOR  ),
        .DENOMINATOR (DENOMINATOR),
        .TIMER_WIDTH (TIMER_WIDTH)
    ) u_synctimer_timer (
        .reset (reset),
        .clk   (clk  ),
        .
        set_time  (timer_set_time ),
        .set_valid (timer_set_valid),
        .
        adjust_sign  (adjust_sign ),
        .adjust_valid (adjust_valid),
        .adjust_ready (adjust_ready),
        .
        current_time (current_time)
    );

    always_comb begin
        timer_set_time  = 'x;
        timer_set_valid = 1'b0;

        if (set_valid) begin
            timer_set_time  = set_time;
            timer_set_valid = set_valid;
        end else if (override_request || correct_override) begin
            timer_set_time  = correct_time;
            timer_set_valid = correct_valid;
        end
    end
endmodule
