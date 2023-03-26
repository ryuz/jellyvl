module jellyvl_etherneco_synctimer_slave #(
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

    input logic adj_enable,

    output logic [TIMER_WIDTH-1:0] current_time,

    // command
    input logic          cmd_rx_start ,
    input logic          cmd_rx_end   ,
    input logic          cmd_rx_error ,
    input logic [16-1:0] cmd_rx_length,
    input logic [8-1:0]  cmd_rx_type  ,
    input logic [8-1:0]  cmd_rx_node  ,

    input  logic          s_cmd_first,
    input  logic          s_cmd_last ,
    input  logic [16-1:0] s_cmd_pos  ,
    input  logic [8-1:0]  s_cmd_data ,
    input  logic          s_cmd_valid,
    output logic [8-1:0]  m_cmd_data ,
    output logic          m_cmd_valid,

    // downstream
    input logic          res_rx_start ,
    input logic          res_rx_end   ,
    input logic          res_rx_error ,
    input logic [16-1:0] res_rx_length,
    input logic [8-1:0]  res_rx_type  ,
    input logic [8-1:0]  res_rx_node  ,

    input  logic          s_res_first,
    input  logic          s_res_last ,
    input  logic [16-1:0] s_res_pos  ,
    input  logic [8-1:0]  s_res_data ,
    input  logic          s_res_valid,
    output logic [8-1:0]  m_res_data ,
    output logic          m_res_valid
);

    // ---------------------------------
    //  Timer
    // ---------------------------------

    localparam type t_time      = logic [8-1:0][8-1:0];
    localparam type t_adj_limit = logic [ADJ_LIMIT_WIDTH-1:0];
    localparam type t_adj_error = logic [ADJ_ERROR_WIDTH-1:0];
    (* mark_debug="true" *)
    logic correct_override;
    (* mark_debug="true" *)
    logic [TIMER_WIDTH-1:0] correct_time;
    (* mark_debug="true" *)
    logic correct_valid;
    (* mark_debug="true" *)
    logic [TIMER_WIDTH-1:0] dbg_current_time;
    assign dbg_current_time = current_time;

    jellyvl_synctimer_core #(
        .TIMER_WIDTH         (TIMER_WIDTH        ),
        .NUMERATOR           (NUMERATOR          ),
        .DENOMINATOR         (DENOMINATOR        ),
        .ADJ_LIMIT_WIDTH     (ADJ_LIMIT_WIDTH    ),
        .ADJ_TIMER_WIDTH     (ADJ_TIMER_WIDTH    ),
        .ADJ_CYCLE_WIDTH     (ADJ_CYCLE_WIDTH    ),
        .ADJ_ERROR_WIDTH     (ADJ_ERROR_WIDTH    ),
        .ADJ_ERROR_Q         (ADJ_ERROR_Q        ),
        .ADJ_ADJUST_WIDTH    (ADJ_ADJUST_WIDTH   ),
        .ADJ_ADJUST_Q        (ADJ_ADJUST_Q       ),
        .ADJ_LPF_GAIN_CYCLE  (ADJ_LPF_GAIN_CYCLE ),
        .ADJ_LPF_GAIN_PERIOD (ADJ_LPF_GAIN_PERIOD),
        .ADJ_LPF_GAIN_PHASE  (ADJ_LPF_GAIN_PHASE ),
        .DEBUG               (DEBUG              ),
        .SIMULATION          (SIMULATION         )
    ) u_synctimer_core (
        .reset (reset),
        .clk   (clk  ),
        .
        adj_param_limit_min  (t_adj_limit'(-100000)),
        .adj_param_limit_max  (t_adj_limit'(+100000)),
        .adj_param_adjust_min (t_adj_error  '(-1000)),
        .adj_param_adjust_max (t_adj_error  '(+1000)),
        .
        set_time  ('0  ),
        .set_valid (1'b0),
        .
        current_time (current_time),
        .
        correct_override (correct_override          ),
        .correct_time     (correct_time              ),
        .correct_valid    (correct_valid & adj_enable)
    );


    // 応答時間補正
    localparam type     t_offset     = logic [4-1:0][8-1:0];
    t_offset start_time  ;
    t_offset elapsed_time;

    always_ff @ (posedge clk) begin
        if (cmd_rx_start) begin
            start_time <= t_offset'(current_time);
        end

        if (res_rx_start) begin
            elapsed_time <= t_offset'(current_time) - start_time;
        end
    end


    // ---------------------------------
    //  Upstream (receive request)
    // ---------------------------------

    localparam type t_position = logic [16-1:0];

    logic up_reset;
    assign up_reset = reset || cmd_rx_error;

    logic      [8-1:0] cmd_rx_cmd       ;
    t_time             cmd_rx_time      ;
    logic      [8-1:0] cmd_rx_time_bit  ;
    t_offset           cmd_rx_offset    ;
    t_position         cmd_rx_offset_pos;
    logic      [4-1:0] cmd_rx_offset_bit;

    always_ff @ (posedge clk) begin
        if (up_reset) begin
            cmd_rx_cmd        <= 'x;
            cmd_rx_time       <= 'x;
            cmd_rx_time_bit   <= 'x;
            cmd_rx_offset     <= 'x;
            cmd_rx_offset_pos <= 'x;
            cmd_rx_offset_bit <= 'x;
        end else begin
            cmd_rx_offset_pos <= t_position'((9 + 4 * (int'(cmd_rx_node) - 1) - 1));

            if (s_cmd_valid) begin
                cmd_rx_time_bit   <= cmd_rx_time_bit   << (1);
                cmd_rx_offset_bit <= cmd_rx_offset_bit << (1);

                // command
                if (s_cmd_first) begin
                    cmd_rx_cmd      <= s_cmd_data;
                    cmd_rx_time_bit <= 8'b00000001;
                end

                // time
                for (int i = 0; i < 8; i++) begin
                    if (cmd_rx_time_bit[i]) begin
                        cmd_rx_time[i] <= s_cmd_data;
                    end
                end

                // offset
                if (s_cmd_pos == cmd_rx_offset_pos) begin
                    cmd_rx_offset_bit <= 4'b0001;
                end
                for (int i = 0; i < 4; i++) begin
                    if (cmd_rx_offset_bit[i]) begin
                        cmd_rx_offset[i] <= s_cmd_data;
                    end
                end
            end
        end
    end

    assign m_cmd_data  = 'x;
    assign m_cmd_valid = 1'b0;


    // ---------------------------------
    //  Downstream (send response)
    // ---------------------------------

    logic down_reset;
    assign down_reset = reset || res_rx_error;

    int res_pos;

    always_ff @ (posedge clk) begin
        if (up_reset) begin
            res_pos     <= 'x;
            m_res_data  <= 'x;
            m_res_valid <= 1'b0;
        end else begin
            res_pos     <= 9 + (int'(cmd_rx_node) - 1) * 4;
            m_res_data  <= 'x;
            m_res_valid <= 1'b0;
            if (s_res_valid) begin
                for (int i = 0; i < 4; i++) begin
                    if (int'(s_res_pos) == res_pos + i) begin
                        m_res_data  <= elapsed_time[i];
                        m_res_valid <= 1'b1;
                    end
                end
            end
        end
    end

    always_ff @ (posedge clk) begin
        if (up_reset) begin
            correct_override <= 1'bx;
            correct_time     <= 'x;
            correct_valid    <= 1'b0;
        end else begin
            correct_override <= 1'bx;
            correct_time     <= cmd_rx_time + t_time'(cmd_rx_offset);
            correct_valid    <= 1'b0;

            if (cmd_rx_end) begin
                correct_override <= cmd_rx_cmd[1];
                correct_valid    <= cmd_rx_cmd[0];
            end
        end
    end

    if (DEBUG) begin :dbg_monitor
        (* mark_debug="true" *)
        logic          dbg_cmd_rx_start;
        (* mark_debug="true" *)
        logic          dbg_res_rx_start;
        (* mark_debug="true" *)
        logic [32-1:0] dbg_start_time  ;
        (* mark_debug="true" *)
        logic [32-1:0] dbg_elapsed_time;

        always_ff @ (posedge clk) begin
            dbg_cmd_rx_start <= cmd_rx_start;
            dbg_res_rx_start <= res_rx_start;
            dbg_start_time   <= start_time;
            dbg_elapsed_time <= elapsed_time;
        end
    end


    // monitor (debug)
    if (SIMULATION) begin :sim_monitor
        localparam type           t_monitor_time       = logic [32-1:0];
        t_monitor_time monitor_cmd_rx_start;
        t_monitor_time monitor_cmd_rx_end  ;
        t_monitor_time monitor_res_rx_start;
        t_monitor_time monitor_res_rx_end  ;
        always_ff @ (posedge clk) begin
            if (cmd_rx_start) begin
                monitor_cmd_rx_start <= t_monitor_time'(current_time);
            end
            if (cmd_rx_end) begin
                monitor_cmd_rx_end <= t_monitor_time'(current_time);
            end
            if (res_rx_start) begin
                monitor_res_rx_start <= t_monitor_time'(current_time);
            end
            if (res_rx_end) begin
                monitor_res_rx_end <= t_monitor_time'(current_time);
            end
        end
    end
endmodule
