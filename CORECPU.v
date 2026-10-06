module CORECPU (
    //CORE RST and CLK
    input core_clk,
    input core_rst,
    //from cache
    input [31:0] RDATA, // data from cache
    input done_cache, //active high and normally 0 
    //to cache
    output req_cache, //request active high held until done has coma
    output [31:0] WDATA,
    output [13:0] req_addr,//14 bit addr
    //from PROGMEM
    input [31:0] instr_from_PROGMEM,
    //to PROGMEM
    output reg [11:0]PC,
    ///below is done for verification only 
    //GPR intentionally making unpacked for better access
    output reg [31:0]R[15:0]
);
localparam OP_NOP       = 8'h00;

wire [11:0]PC_EX;//from EX
///when flush comes from Fetch has to do all 0 as instr to avoid sending stale values note
wire done_MEM,done_MEMr,done_EX;
//MEM will create a stall nonetheless 1cyc

//connects to IDProcess 
//written for Forwarding check herer first and then check at cache paths
wire [31:0]ALU_out;// 32 value
wire [31:0]MEM_out;
wire [4:0]ALU_out_m;//1-valid 4 which register meta 
wire [4:0]MEM_out_m;
//wriiten by fetch process
//done process wil handle the movement with dones by other process
//if a process doesnt produce a done the next process iwll get OP_NOP - Stalling

wire [7:0]EX_op,MEM_op,WB_op;
wire [3:0]EX_Rd,EX_Rs1,EX_Rs2,MEM_Rd,MEM_Rs1,MEM_Rs2;
wire [11:0]MEM_IMM,EX_IMM;
    //it is noted WB will be alwasys 1 done
wire flush,wait_forwarding_mem,halting;
reg [31:0] instr_from_fetch;///conect to IDProcess
//halts Decode and fetch process not WB and MEM still will move MEM to WB not others 
ALUProcess AP (
    .ALU_outo             (ALU_out),
    .ALU_out_mo           (ALU_out_m),
    .OPC                  (EX_op),
    .Rd                   (EX_Rd),
    .Rs1                  (EX_Rs1),
    .Rs2                  (EX_Rs2),
    .IMM                  (EX_IMM),
    .R                    (R),
    .wait_forwarding_mem  (wait_forwarding_mem),
    .clk                  (core_clk),
    .rst                  (core_rst),
    .done                 (done_EX),
    .flush                (flush),
    .MEM_out              (MEM_out),
    .MEM_out_m            (MEM_out_m),
    .done_MEMr            (done_MEMr),
    .PC                   (PC_EX),
    .halting              (halting)
);


IDProcess IDP (
    .clk                  (core_clk),
    .rst                  (core_rst),
    .done_MEM             (done_MEM),
    .done_MEMr            (done_MEMr),
    .done_EX              (done_EX),
    .flush                (flush),
    .wait_forwarding_mem  (wait_forwarding_mem),
    .instr_from_fetch     (instr_from_fetch),
    .EX_op                (EX_op),
    .MEM_op               (MEM_op),
    .WB_op                (WB_op),
    .EX_Rd                (EX_Rd),
    .MEM_Rd               (MEM_Rd),
    .EX_Rs1               (EX_Rs1),
    .MEM_Rs1              (MEM_Rs1),
    .EX_Rs2               (EX_Rs2),
    .MEM_Rs2              (MEM_Rs2),
    .EX_IMM               (EX_IMM),
    .MEM_IMM              (MEM_IMM)
);

//1 clk latency by below but safer ig 
always@(posedge core_clk or negedge core_rst)begin
    if(!core_rst)begin
        instr_from_fetch<=0;
    end
    else if(flush)begin//will flush
        instr_from_fetch<=0;
    end
    else if(halting)begin
        instr_from_fetch<=instr_from_fetch;
    end
    else begin
        instr_from_fetch<=instr_from_PROGMEM;
    end
end

//MEMPRocess Fully pending 

//PC update
always @(posedge core_clk or negedge core_rst) begin
    if(!core_rst)begin
        PC<=0;
    end
    //pending 
   else  if(halting)
    begin
        PC<=PC;
    end
    else if(flush) begin
        PC<=PC_EX;
    end
    else if(done_EX) begin
        PC<=PC+1;//removing ID dependency 
    end
end


//
//Control spine is divided ALU controls Flush ID controls the instruction flow
//MEM delays whole flow if presetn 
//ALU and MEM has their own Hold registers for forwarding usage.
     //\     /\\
    //  (. .)  \\
   //    (!)    \\
// always @(posedge core_clk or negedge core_rst) begin
//     if(!core_rst)begin

//     end
// end


//WB
//so write to all GPR 
integer i_reset;
always @(posedge core_clk or negedge core_rst) begin
    if(!core_rst)begin
        for (i_reset = 0; i_reset < 16; i_reset = i_reset + 1)
            R[i_reset] <= '0;
    end
    else begin
        if(WB_op!=OP_NOP)
        begin
            if(MEM_out_m[4])begin
                R[MEM_out_m[3:0]]<=MEM_out;
            end
                else if(ALU_out_m[4])
            begin
                R[ALU_out_m[3:0]]<=ALU_out;
            end
        end
    end
end


// always@(*)begin
//     if(OPCODE[2]!=OP_NOP)


// end



//alu maker











    
endmodule