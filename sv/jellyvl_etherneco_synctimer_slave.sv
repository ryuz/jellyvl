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

    input logic rx_start,
    input logic rx_error,
    input logic rx_end  ,

    input logic         s_first,
    input logic         s_last ,
    input logic [8-1:0] s_data ,
    input logic         s_valid,

    output logic         m_first,
    output logic         m_last ,
    output logic [8-1:0] m_data ,
    output logic         m_valid
);

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

    logic local_reset;
    assign local_reset = reset || rx_error;

    localparam type t_count = logic [16-1:0];

    logic            busy      ;
    t_count          count     ;
    logic   [8-1:0]  rx_node_id;
    logic   [8-1:0]  rx_cmd    ;
    t_time           rx_time   ;
    logic   [16-1:0] rx_offset ;

    always_ff @ (posedge clk) begin
        if (local_reset) begin
            busy       <= 1'b0;
            count      <= '0;
            rx_node_id <= 'x;
            rx_cmd     <= 'x;
            rx_time    <= 'x;
            rx_offset  <= 'x;

            m_first <= 'x;
            m_last  <= 'x;
            m_data  <= 'x;
            m_valid <= 1'b0;
        end else begin
            m_first <= s_first;
            m_last  <= s_last;
            m_data  <= s_data;
            m_valid <= s_valid;

            if (s_valid) begin
                count <= count + 1'b1;

                if (!busy) begin
                    m_valid <= 1'b0;
                    if (s_first) begin
                        busy       <= 1'b1;
                        count      <= '0;
                        rx_node_id <= s_data;
                        m_data     <= s_data + 1;
                        m_valid    <= s_valid;
                    end
                end else begin
                    case (int'(count))
                        0: begin
                            rx_cmd <= s_data;
                        end
                        1: begin
                            rx_time[0 * 8+:8] <= s_data;
                        end
                        2: begin
                            rx_time[1 * 8+:8] <= s_data;
                        end
                        3: begin
                            rx_time[2 * 8+:8] <= s_data;
                        end
                        4: begin
                            rx_time[3 * 8+:8] <= s_data;
                        end
                        5: begin
                            rx_time[4 * 8+:8] <= s_data;
                        end
                        6: begin
                            rx_time[5 * 8+:8] <= s_data;
                        end
                        7: begin
                            rx_time[6 * 8+:8] <= s_data;
                        end
                        8: begin
                            rx_time[7 * 8+:8] <= s_data;
                        end
                        9: begin
                            rx_offset[0 * 8+:8] <= s_data;
                        end
                        10: begin
                            rx_offset[1 * 8+:8] <= s_data;
                        end
                        default: begin
                            busy <= 1'b0;
                        end
                    endcase
                    if (s_last) begin
                        busy <= 1'b0;
                    end
                end
            end
            if (rx_start || rx_end || rx_error) begin
                busy <= 1'b0;
            end
        end
    end

    always_ff @ (posedge clk) begin
        if (reset) begin
            correct_override <= 1'bx;
            correct_time     <= 'x;
            correct_valid    <= 1'b0;
        end else begin
            correct_override <= 1'bx;
            correct_time     <= rx_time + t_time'(rx_offset);
            correct_valid    <= 1'b0;

            if (rx_end) begin
                if (rx_cmd == 8'h10) begin
                    correct_override <= 1'b1;
                    correct_valid    <= 1'b1;
                end else begin
                    correct_override <= 1'b0;
                    correct_valid    <= 1'b1;
                end
            end
        end
    end

endmodule
