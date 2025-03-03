module jellyvl_etherneco_synctimer_slave #(
    parameter int unsigned TIMER_WIDTH           = 64                                 , // タイマのbit幅
    parameter int unsigned NUMERATOR             = 10                                 , // クロック周期の分子
    parameter int unsigned DENOMINATOR           = 3                                  , // クロック周期の分母
    parameter int unsigned LIMIT_WIDTH           = TIMER_WIDTH                        , // 補正限界のbit幅
    parameter int unsigned CALC_WIDTH            = 32                                 , // 補正に使う範囲のタイマ幅
    parameter int unsigned CYCLE_WIDTH           = 32                                 , // 自クロックサイクルカウンタのbit数
    parameter int unsigned ERROR_WIDTH           = 32                                 , // 誤差計算時のbit幅
    parameter int unsigned ERROR_Q               = 8                                  , // 誤差計算時に追加する固定小数点数bit数
    parameter int unsigned ADJUST_WIDTH          = CYCLE_WIDTH + ERROR_Q              , // 補正周期のbit幅
    parameter int unsigned ADJUST_Q              = ERROR_Q                            , // 補正周期に追加する固定小数点数bit数
    parameter int unsigned LPF_GAIN_CYCLE        = 6                                  , // 自クロックサイクルカウントLPFの更新ゲイン(1/2^N)
    parameter int unsigned LPF_GAIN_PERIOD       = 6                                  , // 周期補正のLPFの更新ゲイン(1/2^N)
    parameter int unsigned LPF_GAIN_PHASE        = 6                                  , // 位相補正のLPFの更新ゲイン(1/2^N)
    parameter int unsigned WB_ADR_WIDTH          = 16                                 ,
    parameter int unsigned WB_DAT_WIDTH          = 32                                 ,
    parameter int unsigned WB_SEL_WIDTH          = WB_DAT_WIDTH / 8                   ,
    parameter type         t_adj_bit             = logic [1-1:0]                      ,
    parameter type         t_adj_time            = logic [CALC_WIDTH-1:0]             ,
    parameter type         t_adj_value           = /*signed*/ logic [ADJUST_WIDTH + ADJUST_Q-1:0],
    parameter type         t_error               = /*signed*/ logic [ERROR_WIDTH-1:0]            ,
    parameter type         t_limit               = /*signed*/ logic [LIMIT_WIDTH-1:0]            ,
    parameter type         t_time                = logic [TIMER_WIDTH-1:0]            ,
    parameter type         t_wb_adr              = logic [WB_ADR_WIDTH-1:0]           ,
    parameter type         t_wb_dat              = logic [WB_DAT_WIDTH-1:0]           ,
    parameter type         t_wb_sel              = logic [WB_SEL_WIDTH-1:0]           ,
    parameter t_limit      INIT_PARAM_LIMIT_MIN  = t_limit'(-100000                  ),
    parameter t_limit      INIT_PARAM_LIMIT_MAX  = t_limit'(+100000                  ),
    parameter t_error      INIT_PARAM_ADJUST_MIN = t_error'(-1000                    ),
    parameter t_error      INIT_PARAM_ADJUST_MAX = t_error'(+1000                    ),

    parameter bit DEBUG      = 1'b0,
    parameter bit SIMULATION = 1'b0
) (
    input logic rst,
    input logic clk,

    input  logic [WB_ADR_WIDTH-1:0] s_wb_adr_i,
    output logic [WB_DAT_WIDTH-1:0] s_wb_dat_o,
    input  logic [WB_DAT_WIDTH-1:0] s_wb_dat_i,
    input  logic [WB_SEL_WIDTH-1:0] s_wb_sel_i,
    input  logic                    s_wb_we_i ,
    input  logic                    s_wb_stb_i,
    output logic                    s_wb_ack_o,

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

    function automatic t_wb_dat WriteMask(
        input t_wb_dat regs,
        input t_wb_dat dat ,
        input t_wb_sel sel 
    ) ;
        t_wb_dat     result;
        for (int unsigned i = 0; i < WB_DAT_WIDTH; i++) begin
            result[i] = ((sel[i / 8]) ? ( dat[i] ) : ( regs[i] ));
        end
        return result;
    endfunction

    localparam t_wb_adr ADR_CORE_ID          = t_wb_adr'(32'h00);
    localparam t_wb_adr ADR_RECV_VALID       = t_wb_adr'(32'h20);
    localparam t_wb_adr ADR_CORRECT_TIME     = t_wb_adr'(32'h21);
    localparam t_wb_adr ADR_LOCAL_TIME       = t_wb_adr'(32'h22);
    localparam t_wb_adr ADR_OVERRIDE_EN      = t_wb_adr'(32'h30);
    localparam t_wb_adr ADR_OVERRIDE_VALUE   = t_wb_adr'(32'h31);
    localparam t_wb_adr ADR_PARAM_LIMIT_MIN  = t_wb_adr'(32'h40);
    localparam t_wb_adr ADR_PARAM_LIMIT_MAX  = t_wb_adr'(32'h41);
    localparam t_wb_adr ADR_PARAM_ADJUST_MIN = t_wb_adr'(32'h42);
    localparam t_wb_adr ADR_PARAM_ADJUST_MAX = t_wb_adr'(32'h43);

    t_adj_bit   reg_recv_valid      ;
    t_adj_bit   reg_override_en     ;
    t_adj_value reg_override_value  ;
    t_limit     reg_param_limit_min ;
    t_limit     reg_param_limit_max ;
    t_error     reg_param_adjust_min;
    t_error     reg_param_adjust_max;

    t_time monitor_correct_time ;
    logic  monitor_correct_renew;
    logic  monitor_correct_valid;

    always_ff @ (posedge clk) begin
        if (rst) begin
            reg_recv_valid     <= '0;
            reg_override_en    <= '0;
            reg_override_value <= '0;

            reg_param_limit_min  <= '0;
            reg_param_limit_max  <= '0;
            reg_param_adjust_min <= '0;
            reg_param_adjust_max <= '0;

        end else begin
            if (s_wb_stb_i && s_wb_we_i) begin
                case (s_wb_adr_i) inside
                    ADR_RECV_VALID    : reg_recv_valid     <= t_adj_bit'(WriteMask(t_wb_dat'(reg_recv_valid), s_wb_dat_i, s_wb_sel_i));
                    ADR_OVERRIDE_EN   : reg_override_en    <= t_adj_bit'(WriteMask(t_wb_dat'(reg_override_en), s_wb_dat_i, s_wb_sel_i));
                    ADR_OVERRIDE_VALUE: reg_override_value <= t_adj_value'(WriteMask(t_wb_dat'(reg_override_value), s_wb_dat_i, s_wb_sel_i));
                    default           : begin
                                        end
                endcase
            end
        end
    end

    always_comb begin
        s_wb_dat_o = '0;
        case (s_wb_adr_i) inside
            ADR_CORE_ID       : s_wb_dat_o = t_wb_dat'(32'hffff1122);
            ADR_RECV_VALID    : s_wb_dat_o = t_wb_dat'(reg_recv_valid);
            ADR_CORRECT_TIME  : s_wb_dat_o = t_wb_dat'(0);
            ADR_LOCAL_TIME    : s_wb_dat_o = t_wb_dat'(0);
            ADR_OVERRIDE_EN   : s_wb_dat_o = t_wb_dat'(reg_override_en);
            ADR_OVERRIDE_VALUE: s_wb_dat_o = t_wb_dat'(reg_override_value);
            default           : begin
                                end
        endcase
    end

    always_comb s_wb_ack_o = s_wb_stb_i;


    // core
    jellyvl_etherneco_synctimer_slave_core #(
        .TIMER_WIDTH     (TIMER_WIDTH    ),
        .NUMERATOR       (NUMERATOR      ),
        .DENOMINATOR     (DENOMINATOR    ),
        .LIMIT_WIDTH     (LIMIT_WIDTH    ),
        .CALC_WIDTH      (CALC_WIDTH     ),
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
    ) u_etherneco_synctimer_slave_core (
        .rst (rst),
        .clk (clk),
        .
        adj_enable   (adj_enable  ),
        .current_time (current_time),
        .
        param_limit_min  (reg_param_limit_min ),
        .param_limit_max  (reg_param_limit_max ),
        .param_adjust_min (reg_param_adjust_min),
        .param_adjust_max (reg_param_adjust_max),
        .
        monitor_correct_time  (monitor_correct_time ),
        .monitor_correct_renew (monitor_correct_renew),
        .monitor_correct_valid (monitor_correct_valid),
        .
        cmd_rx_start  (cmd_rx_start ),
        .cmd_rx_end    (cmd_rx_end   ),
        .cmd_rx_error  (cmd_rx_error ),
        .cmd_rx_length (cmd_rx_length),
        .cmd_rx_type   (cmd_rx_type  ),
        .cmd_rx_node   (cmd_rx_node  ),
        .
        s_cmd_first (s_cmd_first),
        .s_cmd_last  (s_cmd_last ),
        .s_cmd_pos   (s_cmd_pos  ),
        .s_cmd_data  (s_cmd_data ),
        .s_cmd_valid (s_cmd_valid),
        .m_cmd_data  (m_cmd_data ),
        .m_cmd_valid (m_cmd_valid),
        .
        res_rx_start  (res_rx_start ),
        .res_rx_end    (res_rx_end   ),
        .res_rx_error  (res_rx_error ),
        .res_rx_length (res_rx_length),
        .res_rx_type   (res_rx_type  ),
        .res_rx_node   (res_rx_node  ),
        .
        s_res_first (s_res_first),
        .s_res_last  (s_res_last ),
        .s_res_pos   (s_res_pos  ),
        .s_res_data  (s_res_data ),
        .s_res_valid (s_res_valid),
        .m_res_data  (m_res_data ),
        .m_res_valid (m_res_valid)
    );
endmodule
//# sourceMappingURL=jellyvl_etherneco_synctimer_slave.sv.map
