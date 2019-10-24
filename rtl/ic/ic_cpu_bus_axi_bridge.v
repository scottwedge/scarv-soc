
//
// module: ic_cpu_bus_axi_bridge
//
//  Bridge to transform the two request/response channels of the
//  CPU core into the 5 AXI4-Lite bus channels.
//
module ic_cpu_bus_axi_bridge (

input  wire         m0_aclk         , // AXI Clock
input  wire         m0_aresetn      , // AXI Reset

output wire         m0_awvalid      , //
input  wire         m0_awready      , //
output wire [31:0]  m0_awaddr       , //
output wire [ 2:0]  m0_awprot       , //

output wire         m0_wvalid       , //
input  wire         m0_wready       , //
output wire [31:0]  m0_wdata        , //
output wire [ 3:0]  m0_wstrb        , //

input  wire         m0_bvalid       , //
output wire         m0_bready       , //
input  wire [ 1:0]  m0_bresp        , //

output wire         m0_arvalid      , //
input  wire         m0_arready      , //
output wire [31:0]  m0_araddr       , //
output wire [ 2:0]  m0_arprot       , //

input  wire         m0_rvalid       , //
output wire         m0_rready       , //
input  wire [ 1:0]  m0_rresp        , //
input  wire [31:0]  m0_rdata        , //

input  wire         enable          , // Enable requests / does addr map?

input  wire         mem_req         , // Start memory request
output wire         mem_gnt         , // request accepted
input  wire         mem_wen         , // Write enable
input  wire [ 3:0]  mem_strb        , // Write strobe
input  wire [31:0]  mem_wdata       , // Write data
input  wire [31:0]  mem_addr        , // Read/Write address

output wire         mem_recv        , // Instruction memory recieve response.
input  wire         mem_ack         , // Instruction memory ack response.
output wire         mem_error       , // Error
output wire [31:0]  mem_rdata         // Read data
);

//
// Constant assignments
// ------------------------------------------------------------

assign m0_awaddr = mem_addr ;
assign m0_awprot = 3'b000   ; // Unprivilidged, non-secure, Data

assign m0_wdata  = mem_wdata;
assign m0_wstrb  = mem_strb ;

assign m0_araddr = mem_addr ;
assign m0_arprot = 3'b000   ; // Unprivilidged, non-secure, Data

assign mem_rdata = m0_rdata ;

//
// Bus transaction events
// ------------------------------------------------------------

wire    cpu_req = mem_req  && mem_gnt;
wire    cpu_rsp = mem_recv && mem_ack;

wire    axi_rd_req = m0_arvalid && m0_arready;
wire    axi_aw_req = m0_awvalid && m0_awready;
wire    axi_wd_req = m0_wvalid  && m0_wready ;
wire    axi_rd_rsp = m0_rvalid  && m0_rready ;
wire    axi_wr_rsp = m0_bvalid  && m0_bready ;

//
// CPU Bus req/gnt assignments.
// ------------------------------------------------------------

assign mem_gnt  = fsm_idle;

assign mem_recv = fsm_rd_rsp_wait && m0_rvalid ||
                  fsm_wr_rsp_wait && m0_bvalid ;

//
// AXI Bus valid/ready assignments.
// ------------------------------------------------------------

assign m0_arvalid = fsm_idle        && mem_req && !mem_wen ||
                    fsm_rd_req_wait                         ;

assign m0_awvalid = fsm_idle        && mem_req &&  mem_wen ||
                    fsm_wr_req_wait                        ||
                    fsm_wa_req_wait                         ;

assign m0_wvalid  = fsm_idle        && mem_req &&  mem_wen ||
                    fsm_wr_req_wait                        ||
                    fsm_wd_req_wait                         ;

assign m0_rready  = fsm_rd_rsp_wait && mem_recv             ;

assign m0_bready  = fsm_wr_rsp_wait && mem_recv             ;

//
// FSM State handling
// ------------------------------------------------------------

localparam FSM_IDLE         = 3'd0;
localparam FSM_RD_REQ_WAIT  = 3'd1;
localparam FSM_WR_REQ_WAIT  = 3'd2;
localparam FSM_WA_REQ_WAIT  = 3'd3;
localparam FSM_WD_REQ_WAIT  = 3'd4;
localparam FSM_RD_RSP_WAIT  = 3'd5;
localparam FSM_WR_RSP_WAIT  = 3'd6;

reg [2:0]   fsm;
reg [2:0] n_fsm;

wire fsm_idle        = fsm == FSM_IDLE       ;
wire fsm_rd_req_wait = fsm == FSM_RD_REQ_WAIT;
wire fsm_wr_req_wait = fsm == FSM_WR_REQ_WAIT;
wire fsm_wa_req_wait = fsm == FSM_WA_REQ_WAIT;
wire fsm_wd_req_wait = fsm == FSM_WD_REQ_WAIT;
wire fsm_rd_rsp_wait = fsm == FSM_RD_RSP_WAIT;
wire fsm_wr_rsp_wait = fsm == FSM_WR_RSP_WAIT;

always @(*) begin case(fsm)
    FSM_IDLE       : begin
        if(enable && cpu_req && !mem_wen) begin
            // New read request
            if(axi_rd_req) begin
                n_fsm  = FSM_RD_RSP_WAIT;
            end else begin
                n_fsm  = FSM_RD_REQ_WAIT;
            end
        end else if(enable && cpu_req && mem_wen) begin
            // New write request
            if(axi_aw_req && axi_wd_req) begin
                n_fsm = FSM_WR_RSP_WAIT;
            end else if(axi_aw_req) begin
                n_fsm = FSM_WD_REQ_WAIT;
            end else if(axi_wd_req) begin
                n_fsm = FSM_WA_REQ_WAIT;
            end else begin
                n_fsm = FSM_WR_REQ_WAIT;
            end
        end else begin
            n_fsm = FSM_IDLE;
        end
    end
    FSM_RD_REQ_WAIT: begin
        // Has the read request been sent yet?
        n_fsm = axi_rd_req ? FSM_RD_RSP_WAIT : FSM_RD_REQ_WAIT;
    end
    FSM_WR_REQ_WAIT: begin
        // Has any of the write address/data request been accepted yet?
        if(axi_aw_req && axi_wd_req) begin
            n_fsm = FSM_WR_RSP_WAIT;
        end else if(axi_aw_req) begin
            n_fsm = FSM_WD_REQ_WAIT;
        end else if(axi_wd_req) begin
            n_fsm = FSM_WA_REQ_WAIT;
        end else begin
            n_fsm = FSM_WR_REQ_WAIT;
        end
    end
    FSM_WA_REQ_WAIT: begin
        // Waiting for write address to be sent
        n_fsm = axi_aw_req ? FSM_WR_RSP_WAIT : FSM_WA_REQ_WAIT;
    end
    FSM_WD_REQ_WAIT: begin
        // Waiting for write data to be snet.
        n_fsm = axi_aw_req ? FSM_WR_RSP_WAIT : FSM_WD_REQ_WAIT;
    end
    FSM_RD_RSP_WAIT: begin
        // Waiting for read response to be accepted.
        n_fsm = axi_rd_rsp ? FSM_IDLE        : FSM_RD_RSP_WAIT;
    end
    FSM_WR_RSP_WAIT: begin
        // Waiting for write response to be accepted.
        n_fsm = axi_wr_rsp ? FSM_IDLE        : FSM_RD_RSP_WAIT;
    end
    default        : begin
        n_fsm = FSM_IDLE;
    end
endcase end

always @(posedge m0_aclk) begin
    if(!m0_aresetn) begin
        fsm <= FSM_IDLE;
    end else begin
        fsm <= n_fsm;
    end
end

endmodule
