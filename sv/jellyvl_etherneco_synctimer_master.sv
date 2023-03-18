module jellyvl_etherneco_synctimer_master #(
    parameter int unsigned TIMER_WIDTH = 64, // タイマのbit幅
    parameter int unsigned NUMERATOR   = 10, // クロック周期の分子
    parameter int unsigned DENOMINATOR = 3 , // クロック周期の分母
    parameter int unsigned MAX_NODES   = 2 
) (
    input logic reset,
    input logic clk  ,

    output logic [TIMER_WIDTH-1:0] current_time,

    input  logic          cmd_tx_start   ,
    input  logic          cmd_tx_override,
    input  logic          cmd_tx_correct ,
    output logic [16-1:0] cmt_tx_length  ,
    output logic          m_cmd_tx_last  ,
    output logic [8-1:0]  m_cmd_tx_data  ,
    output logic          m_cmd_tx_valid ,
    input  logic          m_cmd_tx_ready ,

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
    localparam type t_time = logic [8-1:0][8-1:0];

    logic adjust_ready;
    jellyvl_synctimer_timer #(
        .NUMERATOR   (NUMERATOR  ),
        .DENOMINATOR (DENOMINATOR),
        .TIMER_WIDTH (TIMER_WIDTH)
    ) u_synctimer_timer (
        .reset (reset),
        .clk   (clk  ),
        .
        set_time  ('0  ),
        .set_valid (1'b0),
        .
        adjust_sign  (1'b0        ),
        .adjust_valid (1'b0        ),
        .adjust_ready (adjust_ready),
        .
        current_time (current_time)
    );

    // 応答時間計測
    localparam type     t_offset     = logic [4-1:0][8-1:0];
    t_offset start_time  ;
    t_offset elapsed_time;

    always_ff @ (posedge clk) begin
        if (cmd_tx_start) begin
            start_time <= t_offset'(current_time);
        end

        if (res_rx_end) begin
            elapsed_time <= t_offset'(current_time) - start_time;
        end
    end

    // オフセット時間
    t_offset offset_time [0:MAX_NODES-1];


    // send command
    localparam type     t_length    = logic [16-1:0];
    localparam t_length CMD_LENGTH  = t_length'((1 + 8 + 4 * MAX_NODES - 1));
    localparam type     t_cmd_count = logic [$clog2(CMD_LENGTH + 1)-1:0];

    assign cmt_tx_length = CMD_LENGTH;

    logic               cmd_busy ;
    t_cmd_count         cmd_count;
    logic       [8-1:0] cmd_cmd  ;
    t_time              cmd_time ;
    logic               cmd_last ;
    logic       [8-1:0] cmd_data ;

    t_cmd_count cmd_count_next;
    assign cmd_count_next = cmd_count + t_cmd_count'(1);

    logic cmd_cke;
    assign cmd_cke = !m_cmd_tx_valid || m_cmd_tx_ready;

    always_ff @ (posedge clk) begin
        if (reset) begin
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
                cmd_cmd   <= {6'd0, cmd_tx_override, cmd_tx_correct};
                cmd_time  <= t_time'(current_time);
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
        if (reset) begin
            m_cmd_tx_last  <= 'x;
            m_cmd_tx_data  <= 'x;
            m_cmd_tx_valid <= 1'b0;
        end else if (cmd_cke) begin
            m_cmd_tx_last  <= cmd_last;
            m_cmd_tx_valid <= cmd_busy;
            if (cmd_count == 0) begin
                m_cmd_tx_data <= cmd_cmd;
            end
            for (int i = 0; i < 8; i++) begin
                if (int'(cmd_count) == 1 + i) begin
                    m_cmd_tx_data <= cmd_time[i];
                end
            end
            for (int i = 0; i < MAX_NODES; i++) begin
                for (int j = 0; j < 4; j++) begin
                    if (int'(cmd_count) == 9 + i * 4 + j) begin
                        m_cmd_tx_data <= offset_time[i][j];
                    end
                end
            end
        end
    end


    // return (bypass)
    assign ret_replace_data  = 'x;
    assign ret_replace_valid = 1'b0;


    // receive response
    t_offset rx_offset    [0:MAX_NODES-1];
    logic    offset_first                ;
    logic    calc_offset                 ;

    always_ff @ (posedge clk) begin
        if (reset) begin
            offset_first <= 1'b1;
            calc_offset  <= 1'b0;
            for (int unsigned i = 0; i < MAX_NODES; i++) begin
                offset_time[i] <= '0;
                rx_offset[i]   <= 'x;
            end
        end else begin
            if (res_payload_valid) begin
                for (int i = 0; i < MAX_NODES; i++) begin
                    for (int j = 0; j < 4; j++) begin
                        if (int'(res_payload_pos) == 9 + i * 4 + j) begin
                            rx_offset[i][j] <= res_payload_data;
                        end
                    end
                end
            end

            calc_offset <= res_rx_end;
            if (calc_offset) begin
                offset_first <= 1'b0;
                for (int unsigned i = 0; i < MAX_NODES; i++) begin
                    if (offset_first) begin
                        offset_time[i] <= elapsed_time - (rx_offset[i] >> 1);
                    end else begin
                        offset_time[i] <= (offset_time[i] * 6 + elapsed_time * 2 - rx_offset[i]) >> 3;
                    end
                end
            end
        end
    end
endmodule
