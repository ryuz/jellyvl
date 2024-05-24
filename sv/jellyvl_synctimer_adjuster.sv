
// 調整機構
module jellyvl_synctimer_adjuster #(
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
    input logic rst,
    input logic clk,

    input logic signed [ERROR_WIDTH-1:0] param_adjust_min,
    input logic signed [ERROR_WIDTH-1:0] param_adjust_max,

    input logic [TIMER_WIDTH-1:0] current_time,

    input logic                   correct_renew,
    input logic [TIMER_WIDTH-1:0] correct_time ,
    input logic                   correct_valid,

    output logic adjust_sign ,
    output logic adjust_valid,
    input  logic adjust_ready
);
    localparam int unsigned CYCLE_Q = LPF_GAIN_CYCLE;

    // type
    localparam type t_error = logic signed [ERROR_WIDTH + ERROR_Q-1:0];
    localparam type t_cycle = logic [CYCLE_WIDTH + CYCLE_Q-1:0];

    // 誤差計算
    t_error request_value;
    t_cycle request_cycle;
    logic   request_valid;
    jellyvl_synctimer_adjuster_calc #(
        .TIMER_WIDTH     (TIMER_WIDTH    ),
        .CYCLE_WIDTH     (CYCLE_WIDTH    ),
        .ERROR_WIDTH     (ERROR_WIDTH    ),
        .ERROR_Q         (ERROR_Q        ),
        .ADJUST_WIDTH    (ADJUST_WIDTH   ),
        .ADJUST_Q        (ADJUST_Q       ),
        .LPF_GAIN_CYCLE  (LPF_GAIN_CYCLE ),
        .LPF_GAIN_PERIOD (LPF_GAIN_PERIOD),
        .LPF_GAIN_PHASE  (LPF_GAIN_PHASE ),
        .DEBUG           (DEBUG          ),
        .SIMULATION      (SIMULATION     )
    ) u_synctimer_adjuster_calc (
        .rst              (rst             ),
        .clk              (clk             ),
        .param_adjust_min (param_adjust_min),
        .param_adjust_max (param_adjust_max),
        .current_time     (current_time    ),
        .correct_renew    (correct_renew   ),
        .correct_time     (correct_time    ),
        .correct_valid    (correct_valid   ),
        .request_value    (request_value   ),
        .request_cycle    (request_cycle   ),
        .request_valid    (request_valid   )
    );


    // 調整パルスドライブ
    jellyvl_synctimer_adjuster_driver #(
        .CYCLE_WIDTH  (CYCLE_WIDTH ),
        .CYCLE_Q      (CYCLE_Q     ),
        .ERROR_WIDTH  (ERROR_WIDTH ),
        .ERROR_Q      (ERROR_Q     ),
        .ADJUST_WIDTH (ADJUST_WIDTH),
        .ADJUST_Q     (ADJUST_Q    ),
        .DEBUG        (DEBUG       ),
        .SIMULATION   (SIMULATION  )
    ) u_synctimer_adjuster_driver (
        .rst           (rst          ),
        .clk           (clk          ),
        .request_value (request_value),
        .request_cycle (request_cycle),
        .request_valid (request_valid),
        .adjust_sign   (adjust_sign  ),
        .adjust_valid  (adjust_valid ),
        .adjust_ready  (adjust_ready )
    );
endmodule
