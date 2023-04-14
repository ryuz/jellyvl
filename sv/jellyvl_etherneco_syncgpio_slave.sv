module jellyvl_etherneco_syncgpio_slave #(
    parameter int unsigned GLOBAL_BYTES = 4   ,
    parameter int unsigned LOCAL_OFFSET = 0   ,
    parameter int unsigned LOCAL_BYTES  = 4   ,
    parameter bit          DEBUG        = 1'b0,
    parameter bit          SIMULATION   = 1'b0
) (
    input logic reset,
    input logic clk  ,

    input logic [GLOBAL_BYTES-1:0][8-1:0] global_rx_data,
    input logic [GLOBAL_BYTES-1:0][8-1:0] global_tx_mask,
    input logic [GLOBAL_BYTES-1:0][8-1:0] global_tx_data,

    input logic [LOCAL_BYTES-1:0][8-1:0] local_rx_data,
    input logic [LOCAL_BYTES-1:0][8-1:0] local_tx_mask,
    input logic [LOCAL_BYTES-1:0][8-1:0] local_tx_data,

    input logic rx_start,
    input logic rx_end  ,
    input logic rx_error,

    input logic [16-1:0] rx_length,
    input logic [8-1:0]  rx_type  ,
    input logic [8-1:0]  rx_node  ,

    input  logic         s_packet_payload  ,
    input  logic         s_packet_fcs      ,
    input  logic         s_packet_crc_en   ,
    input  logic         s_packet_crc_first,
    input  logic         s_packet_first    ,
    input  logic         s_packet_last     ,
    input  logic [8-1:0] s_packet_data     ,
    input  logic         s_packet_valid    ,
    output logic         s_packet_ready    ,

    output logic         m_packet_payload  ,
    output logic         m_packet_fcs      ,
    output logic         m_packet_crc_en   ,
    output logic         m_packet_crc_first,
    output logic         m_packet_first    ,
    output logic         m_packet_last     ,
    output logic [8-1:0] m_packet_data     ,
    output logic         m_packet_valid    ,
    input  logic         m_packet_ready
);

    /*
    st0_packet_payload  : logic,
    st0_packet_fcs      : logic,
    st0_packet_crc_en   : logic,
    st0_packet_crc_first: logic,
    st0_packet_first    : logic,
    st0_packet_last     : logic,
    st0_packet_data     : logic<8>,
    st0_packet_valid    : logic,
    
    st0_count           :
    */

endmodule
