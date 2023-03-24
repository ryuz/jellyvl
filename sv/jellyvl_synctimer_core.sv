module jellyvl_synctimer_core #(
    parameter int unsigned TIMER_WIDTH         = 64                           , // タイマのbit幅
    parameter int unsigned NUMERATOR           = 10                           , // クロック周期の分子
    parameter int unsigned DENOMINATOR         = 3                            , // クロック周期の分母
    parameter int unsigned ADJ_LIMIT_WIDTH     = TIMER_WIDTH                  , // 補正限界のbit幅
    parameter int unsigned ADJ_TIMER_WIDTH     = 32                           , // 補正に使う範囲のタイマ幅
    parameter int unsigned ADJ_CYCLE_WIDTH     = 32                           , // 自クロックサイクルカウンタのbit数
    parameter int unsigned ADJ_ERROR_WIDTH     = 32                           , // 誤差計算時のbit幅
    parameter int unsigned ADJ_ERROR_Q         = 8                            , // 誤差計算時に追加する固定小数点数bit数
    parameter int unsigned ADJ_ADJUST_WIDTH    = ADJ_CYCLE_WIDTH + ADJ_ERROR_Q, // 補正周期のbit幅
    parameter int unsigned ADJ_ADJUST_Q        = ADJ_ERROR_Q                  , // 補正周期に追加する固定小数点数bit数
    parameter int unsigned ADJ_LPF_GAIN_CYCLE  = 6                            , // 自クロックサイクルカウントLPFの更新ゲイン(1/2^N)
    parameter int unsigned ADJ_LPF_GAIN_PERIOD = 6                            , // 周期補正のLPFの更新ゲイン(1/2^N)
    parameter int unsigned ADJ_LPF_GAIN_PHASE  = 6                            , // 位相補正のLPFの更新ゲイン(1/2^N)
    parameter bit          DEBUG               = 1'b0                         ,
    parameter bit          SIMULATION          = 1'b0                     
) (
    input logic reset,
    input logic clk  ,

    input logic signed [ADJ_LIMIT_WIDTH-1:0] adj_param_limit_min ,
    input logic signed [ADJ_LIMIT_WIDTH-1:0] adj_param_limit_max ,
    input logic signed [ADJ_ERROR_WIDTH-1:0] adj_param_adjust_min,
    input logic signed [ADJ_ERROR_WIDTH-1:0] adj_param_adjust_max,

    input logic [TIMER_WIDTH-1:0] set_time ,
    input logic                   set_valid,

    output logic [TIMER_WIDTH-1:0] current_time,

    input logic                   correct_override,
    input logic [TIMER_WIDTH-1:0] correct_time    ,
    input logic                   correct_valid   

);

    // タイマユニット
    logic [TIMER_WIDTH-1:0] timer_set_time ;
    logic                   timer_set_valid;
    logic                   adjust_sign    ;
    logic                   adjust_valid   ;
    logic                   adjust_ready   ;

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


    // リミッター
    logic override_request;
    jellyvl_synctimer_limitter #(
        .TIMER_WIDTH   (TIMER_WIDTH    ),
        .LIMIT_WIDTH   (ADJ_LIMIT_WIDTH),
        .INIT_OVERRIDE (1'b1           ),
        .DEBUG         (DEBUG          ),
        .SIMULATION    (SIMULATION     )
    ) u_synctimer_limitter (
        .reset (reset),
        .clk   (clk  ),
        .
        param_limit_min (adj_param_limit_min),
        .param_limit_max (adj_param_limit_max),
        .
        current_time (current_time),
        .
        override_request (override_request),
        .
        correct_override (correct_override),
        .correct_time     (correct_time    ),
        .correct_valid    (correct_valid   )
    );



    // 補正ユニット
    jellyvl_synctimer_adjust #(
        .TIMER_WIDTH     (ADJ_TIMER_WIDTH    ),
        .CYCLE_WIDTH     (ADJ_CYCLE_WIDTH    ),
        .ERROR_WIDTH     (ADJ_ERROR_WIDTH    ),
        .ERROR_Q         (ADJ_ERROR_Q        ),
        .ADJUST_WIDTH    (ADJ_ADJUST_WIDTH   ),
        .ADJUST_Q        (ADJ_ADJUST_Q       ),
        .LPF_GAIN_CYCLE  (ADJ_LPF_GAIN_CYCLE ),
        .LPF_GAIN_PERIOD (ADJ_LPF_GAIN_PERIOD),
        .LPF_GAIN_PHASE  (ADJ_LPF_GAIN_PHASE ),
        .
        DEBUG      (DEBUG     ),
        .SIMULATION (SIMULATION)
    ) u_synctimer_adjust (
        .reset (reset),
        .clk   (clk  ),
        .
        current_time (current_time[ADJ_TIMER_WIDTH - 1:0]),
        .
        param_adjust_min (adj_param_adjust_min),
        .param_adjust_max (adj_param_adjust_max),
        .
        correct_override (correct_override | override_request),
        .correct_time     (correct_time[ADJ_TIMER_WIDTH - 1:0]),
        .correct_valid    (correct_valid                      ),
        .
        adjust_sign  (adjust_sign ),
        .adjust_valid (adjust_valid),
        .adjust_ready (adjust_ready)
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
