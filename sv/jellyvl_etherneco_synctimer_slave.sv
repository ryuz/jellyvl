module jellyvl_etherneco_synctimer_slave #(
    parameter int unsigned TIMER_WIDTH       = 64                             , // タイマのbit幅
    parameter int unsigned NUMERATOR         = 10                             , // クロック周期の分子
    parameter int unsigned DENOMINATOR       = 3                              , // クロック周期の分母
    parameter int unsigned ADJ_COUNTER_WIDTH = 32                             , // 自クロックで経過時間カウンタのbit数
    parameter int unsigned ADJ_CALC_WIDTH    = 32                             , // タイマのうち計算に使う部分
    parameter int unsigned ADJ_ERROR_WIDTH   = 32                             , // 誤差計算時のbit幅
    parameter int unsigned ADJ_ERROR_Q       = 8                              , // 誤差計算時に追加する固定小数点数bit数
    parameter int unsigned ADJ_ADJUST_WIDTH  = ADJ_COUNTER_WIDTH + ADJ_ERROR_Q, // 補正周期のbit幅
    parameter int unsigned ADJ_ADJUST_Q      = ADJ_ERROR_Q                    , // 補正周期に追加する固定小数点数bit数
    parameter int unsigned ADJ_PERIOD_WIDTH  = ADJ_ERROR_WIDTH                , // 周期補正に使うbit数
    parameter int unsigned ADJ_PHASE_WIDTH   = ADJ_ERROR_WIDTH                 // 位相補正に使うbit数
) (
    input logic reset,
    input logic clk  ,

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

    localparam type t_adj_phase = logic signed [ADJ_PHASE_WIDTH-1:0];
    localparam type t_time      = logic [TIMER_WIDTH-1:0];

    logic  correct_override;
    t_time correct_time    ;
    logic  correct_valid   ;

    jellyvl_synctimer_core #(
        .TIMER_WIDTH       (TIMER_WIDTH      ),
        .NUMERATOR         (NUMERATOR        ),
        .DENOMINATOR       (DENOMINATOR      ),
        .ADJ_COUNTER_WIDTH (ADJ_COUNTER_WIDTH),
        .ADJ_CALC_WIDTH    (ADJ_CALC_WIDTH   ),
        .ADJ_ERROR_WIDTH   (ADJ_ERROR_WIDTH  ),
        .ADJ_ERROR_Q       (ADJ_ERROR_Q      ),
        .ADJ_ADJUST_WIDTH  (ADJ_ADJUST_WIDTH ),
        .ADJ_ADJUST_Q      (ADJ_ADJUST_Q     ),
        .ADJ_PERIOD_WIDTH  (ADJ_PERIOD_WIDTH ),
        .ADJ_PHASE_WIDTH   (ADJ_PHASE_WIDTH  )
    ) u_synctimer_core (
        .reset (reset),
        .clk   (clk  ),
        .
        adj_param_phase_min (t_adj_phase'(-10)),
        .adj_param_phase_max (t_adj_phase'(+10)),
        .
        set_time  ('0  ),
        .set_valid (1'b0),
        .
        current_time (current_time),
        .
        correct_override (correct_override),
        .correct_time     (correct_time    ),
        .correct_valid    (correct_valid   )
    );

    localparam type     t_time32     = logic [32-1:0];
    t_time32 start_time  ;
    t_time32 elapsed_time;

    always_ff @ (posedge clk) begin
        if (cmd_rx_end) begin
            start_time <= current_time[31:0];
        end

        if (res_rx_start) begin
            elapsed_time <= current_time[31:0] - start_time;
        end
    end


    // ---------------------------------
    //  Upstream (receive request)
    // ---------------------------------

    logic up_reset;
    assign up_reset = reset || cmd_rx_error;

    logic  [8-1:0]  cmd_rx_cmd   ;
    t_time          cmd_rx_time  ;
    logic  [16-1:0] cmd_rx_offset;

    always_ff @ (posedge clk) begin
        if (up_reset) begin
            cmd_rx_cmd    <= 'x;
            cmd_rx_time   <= 'x;
            cmd_rx_offset <= 'x;
        end else begin
            if (s_cmd_valid) begin
                case (int'(s_cmd_pos))
                    0 : cmd_rx_cmd              <= s_cmd_data;
                    1 : cmd_rx_time[0 * 8+:8]   <= s_cmd_data;
                    2 : cmd_rx_time[1 * 8+:8]   <= s_cmd_data;
                    3 : cmd_rx_time[2 * 8+:8]   <= s_cmd_data;
                    4 : cmd_rx_time[3 * 8+:8]   <= s_cmd_data;
                    5 : cmd_rx_time[4 * 8+:8]   <= s_cmd_data;
                    6 : cmd_rx_time[5 * 8+:8]   <= s_cmd_data;
                    7 : cmd_rx_time[6 * 8+:8]   <= s_cmd_data;
                    8 : cmd_rx_time[7 * 8+:8]   <= s_cmd_data;
                    9 : cmd_rx_offset[0 * 8+:8] <= s_cmd_data;
                    10: cmd_rx_offset[1 * 8+:8] <= s_cmd_data;
                endcase
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
                case (cmd_rx_cmd)
                    8'h00: begin
                        correct_override <= 1'bx;
                        correct_valid    <= 1'b0;
                    end
                    8'h01: begin
                        correct_override <= 1'b0;
                        correct_valid    <= 1'b1;
                    end
                    8'h03: begin
                        correct_override <= 1'b1;
                        correct_valid    <= 1'b1;
                    end
                    default: begin
                        correct_override <= 1'b1;
                        correct_valid    <= 1'b1;
                    end
                endcase
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

    logic [16-1:0] res_pos;
    assign res_pos = 9 + cmd_rx_node * 4;

    always_ff @ (posedge clk) begin
        if (up_reset) begin
            m_res_data  <= 'x;
            m_res_valid <= 1'b0;
        end else begin
            m_res_data  <= 'x;
            m_res_valid <= 1'b0;
            if (s_res_valid) begin
                if (s_res_pos == res_pos + 16'd0) begin
                    m_res_data  <= elapsed_time[0 * 8+:8];
                    m_res_valid <= 1'b1;
                end
                if (s_res_pos == res_pos + 16'd1) begin
                    m_res_data  <= elapsed_time[1 * 8+:8];
                    m_res_valid <= 1'b1;
                end
                if (s_res_pos == res_pos + 16'd2) begin
                    m_res_data  <= elapsed_time[2 * 8+:8];
                    m_res_valid <= 1'b1;
                end
                if (s_res_pos == res_pos + 16'd3) begin
                    m_res_data  <= elapsed_time[3 * 8+:8];
                    m_res_valid <= 1'b1;
                end
            end
        end
    end
endmodule
