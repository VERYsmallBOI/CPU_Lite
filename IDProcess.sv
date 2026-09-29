//Decode process iwll write NOP so unncessary writes are stoped
//halts Decode and fetch process not WB and MEM still will move MEM to WB not others 
//ID process wil handle the movement with dones by other process
//if a process doesnt produce a done the next process iwll get NOP - Stalling
module IDProcess(
    input clk,
    input rst,

    input done_MEM,
    input done_MEMr,
    //output reg done_ID,//combo
    input done_EX,
    input flush,
    output reg wait_forwarding_mem,//to ALU PROCESS for MEM backward forward
    //it is noted WB will be alwasys 1 done
    //for forwarding done by ID which it self decides this using MEM's Done and output regs and inpupt regs of ALU instr.
    input [31:0] instr_from_fetch,

    output wire [7:0]  EX_op, MEM_op, WB_op,
    output wire [3:0]  EX_Rd, MEM_Rd,
    output  wire [3:0]  EX_Rs1, MEM_Rs1,
    output wire [3:0]  EX_Rs2, MEM_Rs2,
    output wire [11:0] EX_IMM, MEM_IMM
    ); 
localparam NOP       = 8'h00,
           LOAD      = 8'h01,
           LOAD_IND  = 8'h02,
           LOAD_IMM  = 8'h03,
           STORE     = 8'h04,
           STORE_IND = 8'h05,
           ADD       = 8'h06,
           SUB       = 8'h07,
           MUL       = 8'h08,
           AND       = 8'h09,
           OR        = 8'h0A,
           NOT       = 8'h0B,
           CMP       = 8'h0C,
           EQ        = 8'h0D,
           JMP       = 8'h0E,
           JMP_IF    = 8'h0F,
           XOR       = 8'h10,
           SHL       = 8'h11,
           SHR       = 8'h12,
           SAR       = 8'h13,
           ROL       = 8'h14,
           ROR       = 8'h15,
           ADDI      = 8'h16,
           SUBI      = 8'h17,
           ANDI      = 8'h18,
           ORI       = 8'h19,
           XORI      = 8'h1A,
           MOV       = 8'h1B,
           SLT       = 8'h1C,
           SLTU      = 8'h1D,
           LUI       = 8'h1E,
           BEQ       = 8'h20,
           BNE       = 8'h21,
           BLT       = 8'h22,
           BGE       = 8'h23,
           BLTU      = 8'h24,
           BGEU      = 8'h25,
           JMP_REG   = 8'h26,
           HALT      = 8'hFF;


///shi to go out==> (1) OPCODE and meta for others 
reg [7:0]OPCODE[2:0];
reg [3:0]Rd[1:0];
reg [3:0]Rs1[1:0];
reg [3:0]Rs2[1:0];
reg [11:0]IMM[1:0];
//0 -> ALU/EX 
//1 -> MEM
//2 -> WB
assign EX_op  = OPCODE[0];
assign MEM_op = OPCODE[1];
assign WB_op  = OPCODE[2];

assign EX_Rd  = Rd[0];
assign MEM_Rd = Rd[1];

assign EX_Rs1  = Rs1[0];
assign MEM_Rs1 = Rs1[1];


assign EX_Rs2  = Rs2[0];
assign MEM_Rs2 = Rs2[1];

assign EX_IMM  = IMM[0];
assign MEM_IMM = IMM[1];


reg [7:0]OPCODEr[2:0];
reg [3:0]Rdr[1:0];
reg [3:0]Rs1r[1:0];
reg [3:0]Rs2r[1:0];
reg [11:0]IMMr[1:0];

always@(posedge clk,negedge rst)begin
    if(!rst)begin
        //NOP is default
        OPCODE[0]<=NOP;
        OPCODE[1]<=NOP;
        OPCODE[2]<=NOP;
        // Reset Rd array
        Rd[0] <= 4'b0;
        Rd[1] <= 4'b0;
        

        // Reset Rs1 array
        Rs1[0] <= 4'b0;
        Rs1[1] <= 4'b0;
        

        // Reset Rs2 array
        Rs2[0] <= 4'b0;
        Rs2[1] <= 4'b0;
        

        // Reset IMM array
        IMM[0] <= 12'b0;
        IMM[1] <= 12'b0;
        
    end

    else begin
        // NOP is default
        OPCODE[0]  <= flush?0:OPCODEr[0];
        OPCODE[1]  <= OPCODEr[1];
        OPCODE[2]  <= OPCODEr[2];

        // Reset Rd array
        Rd[0]      <= flush?0:Rdr[0];//can be removed for sta purposes left for cleaniness
        Rd[1]      <= Rdr[1];
        

        // Reset Rs1 array
        Rs1[0]     <= flush?0:Rs1r[0];//can be removed for sta purposes left for cleaniness
        Rs1[1]     <= Rs1r[1];
       

        // Reset Rs2 array
        Rs2[0]     <= flush?0:Rs2r[0];//can be removed for sta purposes left for cleaniness
        Rs2[1]     <= Rs2r[1];
        

        // Reset IMM array
        IMM[0]     <= flush?0:IMMr[0];//can be removed for sta purposes left for cleaniness
        IMM[1]     <= IMMr[1];
        

    end

    end 


always@(*)begin


    //WB instr
    if(done_MEMr)//MOVE forward in WB from MEM and 
            begin
                OPCODEr[2]=OPCODE[1];

            end
    else begin //useless stalled; by lower network
                OPCODEr[2]=NOP;

    end


    //MEM instr
    if(done_EX && done_MEM)begin //MOVE it 
                OPCODEr[1]=OPCODE[0];
                Rdr[1]=Rd[0];
                Rs1r[1]=Rs1[0];
                Rs2r[1]=Rs2[0];
                IMMr[1]=IMM[0];

    end
    else if(done_MEM) begin
                OPCODEr[1]=NOP;
                Rdr[1]=4'b0;
                Rs1r[1]=4'b0;
                Rs2r[1]=4'b0;
                IMMr[1]=4'b0;
    end
    else begin
        OPCODEr[1]=OPCODE[1];
        Rdr[1]=Rd[1];
        Rs1r[1]=Rs1[1];
        Rs2r[1]=Rs2[1];
        IMMr[1]=IMM[1];
    end


    //ALU instru
    if(done_EX)begin //flush on from alu -> remove loading else do it
        OPCODEr[0]=flush?NOP:instr_from_fetch[31:24];
        Rdr[0]=flush?4'b0:instr_from_fetch[23:20];
        Rs1r[0]=flush?4'b0:instr_from_fetch[19:16];
        Rs2r[0]=flush?4'b0:instr_from_fetch[15:12];
        IMMr[0]=flush?12'b0:instr_from_fetch[11:0];
    end
    else begin //hold previous if it ddidnt fininsh
        OPCODEr[0]=OPCODE[0];
        Rdr[0]=Rd[0];
        Rs1r[0]=Rs1[0];
        Rs2r[0]=Rs2[0];
        IMMr[0]=IMM[0];
    end
    
    // if(done_EX)begin    
    //     done_ID=1;
    //     else done_ID=0;
    // end
    //seeing how done_ID is essentially ALU done no need

    end
//
always@(*)begin
    //this seems computtionally heavy and has to besubject to change to better one 
if(((OPCODE[1] == LOAD) || (OPCODE[1] == LOAD_IND)) && (
        // Case 1: Instructions using only RS1
        ( (Rd[1] == Rs1[0]) && (
            (OPCODE[0] == ADDI)    || (OPCODE[0] == SUBI)    || 
            (OPCODE[0] == ANDI)    || (OPCODE[0] == ORI)     || 
            (OPCODE[0] == XORI)    || (OPCODE[0] == NOT)     || 
            (OPCODE[0] == JMP_IF)  || (OPCODE[0] == JMP_REG) || 
            (OPCODE[0] == MOV)
        )) ||
        // Case 2: Instructions using both RS1 and RS2
        ( ((Rd[1] == Rs1[0]) || (Rd[1] == Rs2[0])) && (
            (OPCODE[0] == ADD)  || (OPCODE[0] == SUB)  || 
            (OPCODE[0] == MUL)  || (OPCODE[0] == AND)  || 
            (OPCODE[0] == OR)   || (OPCODE[0] == XOR)  || 
            (OPCODE[0] == EQ)   || (OPCODE[0] == SLT)  || 
            (OPCODE[0] == SLTU) || (OPCODE[0] == CMP)  || 
            (OPCODE[0] == SAR)  || (OPCODE[0] == SHR)  || 
            (OPCODE[0] == SHL)  || (OPCODE[0] == ROR)  || 
            (OPCODE[0] == ROL)
        ))
        // keeping original instr for check it ((OPCODE[1]== 1|| OPCODE[1]== 2)&&(((OPCODE[0] == ADDI) || (OPCODE[0] == SUBI) || (OPCODE[0] == ANDI) || (OPCODE[0] == ORI) || (OPCODE[0] == XORI) || (OPCODE[0] == NOT) || (OPCODE[0] == JMP_IF) || (OPCODE[0] == JMP_REG) || (OPCODE[0] == MOV))&&((Rd[1]==Rs1[0]))||((Rd[1]==Rs2[0]))&&((OPCODE[0] == ADD) || (OPCODE[0] == SUB) || (OPCODE[0] == MUL) || (OPCODE[0] == AND) || (OPCODE[0] == OR) || (OPCODE[0] == XOR) || (OPCODE[0] == EQ) || (OPCODE[0] == SLT) || (OPCODE[0] == SLTU) || (OPCODE[0] == CMP) || (OPCODE[0] == SAR) || (OPCODE[0] == SHR) || (OPCODE[0] == SHL) || (OPCODE[0] == ROR) || (OPCODE[0] == ROL)) ))
    ))begin  //dest on Load matches Rs in EX
    wait_forwarding_mem=1; //so if yes to forading tehn hold d only pplace to meet timing
end
else wait_forwarding_mem=0;
end


endmodule