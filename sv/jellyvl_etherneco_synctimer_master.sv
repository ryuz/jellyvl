module jellyvl_etherneco_synctimer_master #(
    parameter int unsigned TIMER_WIDTH     = 64  , // タイマのbit幅
    parameter int unsigned NUMERATOR       = 10  , // クロック周期の分子
    parameter int unsigned DENOMINATOR     = 3   , // クロック周期の分母
    parameter int unsigned MAX_NODES       = 2   , // 最大ノード数
    parameter int unsigned OFFSET_WIDTH    = 24  , // オフセットbit幅
    parameter int unsigned OFFSET_LPF_GAIN = 4   , // オフセット更新LPFのゲイン (1/2^N)
    parameter bit          DEBUG           = 1'b0,
    parameter bit          SIMULATION      = 1'b0
) (
    input logic rst,
    input logic clk,

    output logic [TIMER_WIDTH-1:0] current_time,

    input logic [TIMER_WIDTH-1:0] set_time ,
    input logic                   set_valid,

    input  logic          cmd_tx_start  ,
    input  logic          cmd_tx_renew  ,
    input  logic          cmd_tx_correct,
    output logic [16-1:0] cmt_tx_length ,
    output logic          m_cmd_tx_last ,
    output logic [8-1:0]  m_cmd_tx_data ,
    output logic          m_cmd_tx_valid,
    input  logic          m_cmd_tx_ready,

    input  logic          ret_rx_start     ,
    input  logic          ret_rx_end       ,
    input  logic          ret_rx_error     ,
    input  logic [16-1:0] ret_rx_length    ,
    input  logic [8-1:0]  ret_rx_type      ,
    input  logic [8-1:0]  ret_rx_node      ,
    input  logic          ret_payload_first,
    input  logic          ret_payload_last ,
    input  logic [16-1:0] ret_payload_pos  ,
    input  logic [8-1:0]  ret_payload_data ,
    input  logic          ret_payload_valid,
    output logic [8-1:0]  ret_replace_data ,
    output logic          ret_replace_valid,

    input logic          res_rx_start     ,
    input logic          res_rx_end       ,
    input logic          res_rx_error     ,
    input logic [16-1:0] res_rx_length    ,
    input logic [8-1:0]  res_rx_type      ,
    input logic [8-1:0]  res_rx_node      ,
    input logic          res_payload_first,
    input logic          res_payload_last ,
    input logic [16-1:0] res_payload_pos  ,
    input logic [8-1:0]  res_payload_data ,
    input logic          res_payload_valid
);


    // タイマ
    localparam type t_time_pkt = logic [8-1:0][8-1:0];

    logic adjust_ready;
    jellyvl_synctimer_timer #(
        .NUMERATOR   (NUMERATOR  ),
        .DENOMINATOR (DENOMINATOR),
        .TIMER_WIDTH (TIMER_WIDTH)
    ) u_synctimer_timer (
        .rst (rst),
        .clk (clk),
        .
        set_time  (set_time ),
        .set_valid (set_valid),
        .
        adjust_sign  (1'b0        ),
        .adjust_valid (1'b0        ),
        .adjust_ready (adjust_ready),
        .
        current_time (current_time)
    );


    // 応答時間計測
    localparam type t_offset = logic [OFFSET_WIDTH-1:0];

    function automatic t_offset CycleToOffset(
        input int unsigned cycle
    ) ;
        return t_offset'((NUMERATOR * cycle / DENOMINATOR));
    endfunction

    t_offset tx_start_time;
    t_offset rx_start_time;
    t_offset rx_end_time  ;
    t_offset total_time   ;
    t_offset response_time;
    t_offset packet_time  ;

    always_ff @ (posedge clk) begin
        if (cmd_tx_start) begin
            tx_start_time <= t_offset'(current_time) - CycleToOffset(2); // 2サイクル補正
        end
        if (res_rx_start) begin
            rx_start_time <= t_offset'(current_time);
            response_time <= t_offset'(current_time) - tx_start_time;
        end
        if (res_rx_end) begin
            rx_end_time <= t_offset'(current_time);
            total_time  <= t_offset'(current_time) - tx_start_time;
            packet_time <= t_offset'(current_time) - rx_start_time;
        end
    end

    // オフセット時間
    localparam type         t_offset_pkt = logic [4-1:0][8-1:0];
    t_offset     offset_gain  [0:MAX_NODES-1];
    t_offset     offset_time  [0:MAX_NODES-1];
    t_offset_pkt offset_pkt   [0:MAX_NODES-1];
    always_comb begin
        for (int signed i = 0; i < MAX_NODES; i++) begin
            offset_pkt[i] = t_offset_pkt'(offset_time[i]);
        end
    end

    // send command
    localparam type     t_length    = logic [16-1:0];
    localparam t_length CMD_LENGTH  = t_length'((1 + 8 + 4 * MAX_NODES - 1));
    localparam type     t_cmd_count = logic [$clog2(CMD_LENGTH + 1)-1:0];

    always_comb cmt_tx_length = CMD_LENGTH;

    logic               cmd_busy ;
    t_cmd_count         cmd_count;
    logic       [8-1:0] cmd_cmd  ;
    t_time_pkt          cmd_time ;
    logic               cmd_last ;
    logic       [8-1:0] cmd_data ;

    t_cmd_count cmd_count_next;
    always_comb cmd_count_next = cmd_count + t_cmd_count'(1);

    logic cmd_cke;
    always_comb cmd_cke = !m_cmd_tx_valid || m_cmd_tx_ready;

    always_ff @ (posedge clk) begin
        if (rst) begin
            cmd_busy  <= 1'b0;
            cmd_count <= 'x;
            cmd_cmd   <= 'x;
            cmd_time  <= 'x;
            cmd_last  <= 'x;
            cmd_data  <= 'x;
        end else begin
            if (cmd_tx_start) begin
                cmd_busy  <= 1'b1;
                cmd_count <= '0;
                cmd_cmd   <= {6'd0, cmd_tx_renew, cmd_tx_correct};
                cmd_time  <= t_time_pkt'(current_time);
            end else if (cmd_cke) begin
                cmd_count <= cmd_count_next;
                cmd_last  <= (cmd_count_next == t_cmd_count'(CMD_LENGTH));
                if (cmd_last) begin
                    cmd_busy  <= 1'b0;
                    cmd_count <= 'x;
                    cmd_cmd   <= 'x;
                    cmd_time  <= 'x;
                    cmd_last  <= 'x;
                end
            end
        end
    end

    always_ff @ (posedge clk) begin
        if (rst) begin
            m_cmd_tx_last  <= 'x;
            m_cmd_tx_data  <= 'x;
            m_cmd_tx_valid <= 1'b0;
        end else if (cmd_cke) begin
            m_cmd_tx_last  <= cmd_last;
            m_cmd_tx_valid <= cmd_busy;
            if (cmd_count == 0) begin
                m_cmd_tx_data <= cmd_cmd;
            end
            for (int signed i = 0; i < 8; i++) begin
                if (cmd_count == 1 + i) begin
                    m_cmd_tx_data <= cmd_time[i];
                end
            end
            for (int signed i = 0; i < MAX_NODES; i++) begin
                for (int signed j = 0; j < 4; j++) begin
                    if (cmd_count == 9 + i * 4 + j) begin
                        m_cmd_tx_data <= offset_pkt[i][j];
                    end
                end
            end
        end
    end


    // return (bypass)
    always_comb ret_replace_data  = 'x;
    always_comb ret_replace_valid = 1'b0;


    // receive response
    t_offset delay_time    [0:MAX_NODES-1];
    t_offset measured_time [0:MAX_NODES-1];

    t_offset_pkt rx_offset_pkt [0:MAX_NODES-1];
    t_offset     rx_offset     [0:MAX_NODES-1];
    always_comb begin
        for (int signed i = 0; i < MAX_NODES; i++) begin
            rx_offset[i] = t_offset'(rx_offset_pkt[i]);
        end
    end

    logic         offset_first;
    logic [3-1:0] calc_wait   ;

    always_ff @ (posedge clk) begin
        if (rst) begin
            offset_first <= 1'b1;
            calc_wait    <= '0;
            for (int unsigned i = 0; i < MAX_NODES; i++) begin
                offset_time[i]   <= '0;
                offset_gain[i]   <= 'x;
                delay_time[i]    <= 'x;
                measured_time[i] <= 'x;
                rx_offset_pkt[i] <= 'x;
            end
        end else begin
            for (int signed i = 0; i < MAX_NODES; i++) begin
                offset_gain[i] <= (offset_time[i] << (OFFSET_LPF_GAIN + 1)) - (offset_time[i] << 1);
            end

            if (res_payload_valid) begin
                for (int signed i = 0; i < MAX_NODES; i++) begin
                    for (int signed j = 0; j < 4; j++) begin
                        if (res_payload_pos == 9 + i * 4 + j) begin
                            rx_offset_pkt[i][j] <= res_payload_data;
                        end
                    end
                end
            end

            // calc
            for (int unsigned i = 0; i < MAX_NODES; i++) begin
                delay_time[i]    <= response_time - t_offset'(rx_offset[i]);
                measured_time[i] <= delay_time[i] + 2 * packet_time; // 2倍の時間
            end

            calc_wait <= {calc_wait[1:0], res_rx_end};
            if (calc_wait[2]) begin
                offset_first <= 1'b0;
                for (int unsigned i = 0; i < MAX_NODES; i++) begin
                    if (offset_first) begin
                        offset_time[i] <= (measured_time[i] >> 1);
                    end else begin
                        offset_time[i] <= (offset_gain[i] + measured_time[i]) >> (OFFSET_LPF_GAIN + 1);
                    end
                end
            end
        end
    end

    if (DEBUG) begin :dbg_monitor
        (* mark_debug="true" *)
        logic dbg_cmd_tx_start;
        (* mark_debug="true" *)
        t_offset dbg_offset_time0;
        (* mark_debug="true" *)
        t_offset dbg_offset_time1;
        (* mark_debug="true" *)
        t_offset dbg_rx_offset0;
        (* mark_debug="true" *)
        t_offset dbg_rx_offset1;
        (* 
        mark_debug="true" *)
        logic dbg_res_payload_first;
        (* mark_debug="true" *)
        logic dbg_res_payload_last;
        (* mark_debug="true" *)
        logic [16-1:0] dbg_res_payload_pos;
        (* mark_debug="true" *)
        logic [8-1:0] dbg_res_payload_data;
        (* mark_debug="true" *)
        logic dbg_res_payload_valid;
        (* 
        mark_debug="true" *)
        t_offset dbg_delay_time0;
        (* mark_debug="true" *)
        t_offset dbg_delay_time1;
        (* mark_debug="true" *)
        t_offset dbg_measured_time0;
        (* mark_debug="true" *)
        t_offset dbg_measured_time1;
        (* 
        mark_debug="true" *)
        t_offset dbg_response_time;

        always_ff @ (posedge clk) begin
            dbg_cmd_tx_start <= cmd_tx_start;
            dbg_offset_time0 <= offset_time[0];
            dbg_offset_time1 <= offset_time[1];
            dbg_rx_offset0   <= rx_offset[0];
            dbg_rx_offset1   <= rx_offset[1];

            dbg_res_payload_first <= res_payload_first;
            dbg_res_payload_last  <= res_payload_last;
            dbg_res_payload_pos   <= res_payload_pos;
            dbg_res_payload_data  <= res_payload_data;
            dbg_res_payload_valid <= res_payload_valid;

            dbg_delay_time0    <= delay_time[0];
            dbg_delay_time1    <= delay_time[1];
            dbg_measured_time0 <= measured_time[0];
            dbg_measured_time1 <= measured_time[1];

            dbg_response_time <= response_time;
        end
    end


    // monitor (debug)
    if (SIMULATION) begin :sim_monitor
        localparam type           t_monitor_time           = logic [32-1:0];
        t_monitor_time sim_monitor_cmd_tx_start;
        t_monitor_time sim_monitor_ret_rx_start;
        t_monitor_time sim_monitor_ret_rx_end  ;
        t_monitor_time sim_monitor_res_rx_start;
        t_monitor_time sim_monitor_res_rx_end  ;
        always_ff @ (posedge clk) begin
            if (cmd_tx_start) begin
                sim_monitor_cmd_tx_start <= t_monitor_time'(current_time);
            end
            if (ret_rx_start) begin
                sim_monitor_ret_rx_start <= t_monitor_time'(current_time);
            end
            if (ret_rx_end) begin
                sim_monitor_ret_rx_end <= t_monitor_time'(current_time);
            end
            if (res_rx_start) begin
                sim_monitor_res_rx_start <= t_monitor_time'(current_time);
            end
            if (res_rx_end) begin
                sim_monitor_res_rx_end <= t_monitor_time'(current_time);
            end
        end
    end
endmodule
//# sourceMappingURL=jellyvl_etherneco_synctimer_master.sv.map
