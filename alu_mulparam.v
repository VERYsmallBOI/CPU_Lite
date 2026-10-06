//for mul use done as uniqueness if another mul comes in so with done clear the State/no of flags assoctiated.
module ALUProcess#(parameter MULN=4)(
    output wire [31:0]ALU_outo,
    output wire [4:0]ALU_out_mo,//1-valid 4 which register meta 
    input [7:0]OPC,
    input [3:0]Rd,
    input [3:0]Rs1,
    input [3:0]Rs2,
    input [11:0]IMM,
    input wire [31:0]R[15:0],//reg bank
    input wait_forwarding_mem,
    input clk,
    input rst,
    output wire done,
    output reg flush,
    input wire [31:0]MEM_out,
    input wire [4:0]MEM_out_m,
    input done_MEMr,
    output reg [11:0]PC,
    output reg halting
);
//MULN can be 1 2 4 8 16 32 
localparam DONE=MULN-1;
localparam SHIFT=(MULN==1)?0:$clog2(32/MULN);
localparam BITGRP=5'(32/MULN);
localparam MUL_state_PARAM = (MULN == 1) ? 1 : $clog2(MULN);

//MEM and ALU process clears the current(0)their own outs only if they have nothing to give
localparam OP_NOP       = 8'h00,
           OP_LOAD      = 8'h01,
           OP_LOAD_IND  = 8'h02,
           OP_LOAD_IMM  = 8'h03,
           OP_STORE     = 8'h04,
           OP_STORE_IND = 8'h05,
           OP_ADD       = 8'h06,
           OP_SUB       = 8'h07,
           OP_MUL       = 8'h08,
           OP_AND       = 8'h09,
           OP_OR        = 8'h0A,
           OP_NOT       = 8'h0B,
           OP_CMP       = 8'h0C,
           OP_EQ        = 8'h0D,
           OP_JMP       = 8'h0E,
           OP_JMP_IF    = 8'h0F,
           OP_XOR       = 8'h10,
           OP_SHL       = 8'h11,
           OP_SHR       = 8'h12,
           OP_SAR       = 8'h13,
           OP_ROL       = 8'h14,
           OP_ROR       = 8'h15,
           OP_ADDI      = 8'h16,
           OP_SUBI      = 8'h17,
           OP_ANDI      = 8'h18,
           OP_ORI       = 8'h19,
           OP_XORI      = 8'h1A,
           OP_MOV       = 8'h1B,
           OP_SLT       = 8'h1C,
           OP_SLTU      = 8'h1D,
           OP_LUI       = 8'h1E,
           OP_BEQ       = 8'h20,
           OP_BNE       = 8'h21,
           OP_BLT       = 8'h22,
           OP_BGE       = 8'h23,
           OP_BLTU      = 8'h24,
           OP_BGEU      = 8'h25,
           OP_JMP_REG   = 8'h26,
           OP_HALT      = 8'hFF;

//can do work without done fomr MEM but cant push to reg until that 
//produces ALU outs and it meta does all the ALU calcs(OP_MUL OP_ADD OP_OR etc)
//OP_MUL uses 
reg [31:0]ALU_out[1:0];// 32 value
reg [4:0]ALU_out_m[1:0];//1-valid 4 which register meta 
reg [31:0]ALU_outr;// 32 value
reg [4:0]ALU_out_mr;//1-valid 4 which register meta 
reg done_from_calc;
reg [3:0]PSR,PSRr;
assign ALU_outo=ALU_out[1];
assign ALU_out_mo=ALU_out_m[1];
reg [31:0]R1,R2;//operands
reg notused;//not used is when the operation result will not be used
wire [4:0]bitstart;
//OP_MUL
reg [MUL_state_PARAM:0]MUL_state,MUL_stater;//4 state 8 pp at once 4 states(0 to 3 MAC in4 wait)
reg [31:0]PP;
reg [31:0]ACC,ACCr;

reg HALTr;
///CALC
always@(posedge clk or negedge rst)begin
    if(!rst)begin
        ALU_out[1]<=0;
        ALU_out[0]<=0;
        ALU_out_m[0]<=0;
        ALU_out_m[1]<=0;
        PSR<=0;
        MUL_state<=0;
        ACC<=0;
        halting<=0;
    end
    else begin
        //wait_forwarding_mem doesnt let it move until the corresponsinf instr move from MEM
        MUL_state<=(((wait_forwarding_mem)||done)?0:MUL_stater);//if waiting or done is present clear
//when it actually finishes afeter forwarding go back to 0 so if next EX is also OP_MUL doesnt fuck it up
        if((~wait_forwarding_mem)||done||(~halting))begin//registered version and anyway flushes
            ALU_out_m[1]<=ALU_out_m[0];
            ALU_out_m[0]<=notused?0:ALU_out_mr;//notsed for cmp
            ALU_out[0]<=notused?0:ALU_outr;
            ALU_out[1]<=ALU_out[0];
            PSR<=PSRr;
        end
        ACC <= (done || (wait_forwarding_mem)) ? 0 : ACCr;
        halting<=HALTr;//all it does is dont give done 
    end 
end

// 2 stuff as result done and actal resutl(flag + reg change)
always@(*)begin
    HALTr=0;
    ACCr=0;//default to 0 
    MUL_stater=0;//only change is at OP_MUL dont let it move in 3 state unless done comes 
    done_from_calc=1;//no latency execpt for mul 
    PP=0;
    notused=0;//OP_CMP OP_JMP Branch 
    flush=0;//OP_JMP Branch (CALL RET -- pending)
    PC=0;//has to be sent combo to flush
    case(OPC)
    OP_ADD:begin
        ALU_out_mr={1'b1,Rd};
        {PSRr[2],ALU_outr}={1'b0,R1}+{1'b0,R2};//2 is C
        PSRr[3]=((R1[31]==R2[31])&&(ALU_outr[31] != R1[31]));//3 is OV
        PSRr[1]=ALU_outr[31];//1 is N
        PSRr[0]=(ALU_outr==0);//0 is Z
    end
    OP_SUB:begin
        ALU_out_mr={1'b1,Rd};
        {PSRr[2],ALU_outr}={1'b0,R1}+{1'b0,~R2}+1'b1;//2 is C
        PSRr[3]=((R1[31]!=R2[31])&&(ALU_outr[31] != R1[31]));//3 is OV
        PSRr[1]=ALU_outr[31];//1 is N
        PSRr[0]=(ALU_outr==0);//0 is Z
    end
    OP_ADDI:begin
        ALU_out_mr={1'b1,Rd};
        {PSRr[2],ALU_outr}={1'b0,R1}+{1'b0,{20{IMM[11]}},IMM};//2 is C Sign exxtension for IMM is needed as per spec
        PSRr[3]=((R1[31]==IMM[11])&&(ALU_outr[31] != R1[31]));//3 is OV
        PSRr[1]=ALU_outr[31];//1 is N
        PSRr[0]=(ALU_outr==0);//0 is Z
    end
    OP_SUBI:begin
        ALU_out_mr={1'b1,Rd};
        {PSRr[2],ALU_outr}={1'b0,R1}+{1'b0,~{{20{IMM[11]}},IMM}}+1'b1;//2 is C
        PSRr[3]=((R1[31]!=IMM[11])&&(ALU_outr[31] != R1[31]));//3 is OV
        PSRr[1]=ALU_outr[31];//1 is N
        PSRr[0]=(ALU_outr==0);//0 is Z
    end
    OP_MUL:begin
        ALU_out_mr={1'b1,Rd};
        done_from_calc=(MUL_state>=(DONE));
        MUL_stater=(MUL_state>(DONE))?MULN:MUL_state+1;
        PP=32'((MUL_state>(DONE))?0:R1*R2[bitstart+:BITGRP]);
        ACCr=32'((MUL_state>(DONE))?ACC:(PP<<bitstart)+ACC);
        ALU_outr=(MUL_state>=(DONE))?ACCr:0;
        PSRr[3]=PSR[3];
        PSRr[1]=(MUL_state>=(DONE))?ALU_outr[31]:PSR[1];
        PSRr[0]=(MUL_state>=(DONE))?(ALU_outr==0):PSR[0];
        PSRr[2]=PSR[2];
    end
    OP_AND:begin
        ALU_out_mr={1'b1,Rd};
        ALU_outr=R1&R2;
        PSRr[3]=PSR[3];//3 is OV
        PSRr[1]=ALU_outr[31];//1 is N
        PSRr[0]=(ALU_outr==0);//0 is Z
        PSRr[2]=PSR[2];
    end
    OP_OR:begin
        ALU_out_mr={1'b1,Rd};
        ALU_outr=R1|R2;
        PSRr[3]=PSR[3];//3 is OV
        PSRr[1]=ALU_outr[31];//1 is N
        PSRr[0]=(ALU_outr==0);//0 is Z
        PSRr[2]=PSR[2];
    end
    OP_NOT:begin
        ALU_out_mr={1'b1,Rd};
        ALU_outr=~R1;
        PSRr[3]=PSR[3];//3 is OV
        PSRr[1]=ALU_outr[31];//1 is N
        PSRr[0]=(ALU_outr==0);//0 is Z
        PSRr[2]=PSR[2];
    end
    OP_XOR:begin
        ALU_out_mr={1'b1,Rd};
        ALU_outr=R1^R2;
        PSRr[3]=PSR[3];//3 is OV
        PSRr[1]=ALU_outr[31];//1 is N
        PSRr[0]=(ALU_outr==0);//0 is Z
        PSRr[2]=PSR[2];
    end
    OP_ANDI:begin
        ALU_out_mr={1'b1,Rd};
        ALU_outr=R1&({20'b0,IMM});//can also be {R1[31:12],IMM^R1[11:0]} but dont want to confuse
        PSRr[3]=PSR[3];//3 is OV
        PSRr[1]=ALU_outr[31];//1 is N
        PSRr[0]=(ALU_outr==0);//0 is Z
        PSRr[2]=PSR[2];
    end
    OP_ORI:begin
        ALU_out_mr={1'b1,Rd};
        ALU_outr=R1|({20'b0,IMM});//can also be {R1[31:12],IMM^R1[11:0]} but dont want to confuse
        PSRr[3]=PSR[3];//3 is OV
        PSRr[1]=ALU_outr[31];//1 is N
        PSRr[0]=(ALU_outr==0);//0 is Z
        PSRr[2]=PSR[2];
    end
    OP_XORI:begin
        ALU_out_mr={1'b1,Rd};
        ALU_outr=R1^({20'b0,IMM});//can also be {R1[31:12],IMM^R1[11:0]} but dont want to confuse
        PSRr[3]=PSR[3];//3 is OV
        PSRr[1]=ALU_outr[31];//1 is N
        PSRr[0]=(ALU_outr==0);//0 is Z
        PSRr[2]=PSR[2];
    end
    ///comparisions
    OP_EQ:begin
        ALU_out_mr=5'b0;
        ALU_outr={31'b0,(R1==R2)};
        PSRr[3]=PSR[3];//3 is OV
        PSRr[1]=PSR[1];//1 is N
        PSRr[0]=~ALU_outr[0];//0 is Z
        PSRr[2]=PSR[2];
    end
    OP_SLT:begin//smalelr than (singedd)
        ALU_outr=($signed(R1)<$signed(R2))?1'b1:1'b0;
        ALU_out_mr={1'b1,Rd};
        PSRr[3]=PSR[3];
        PSRr[2]=PSR[2];
        PSRr[1]=PSR[1];
        PSRr[0]=~ALU_outr[0];//no need for calc
    end
    OP_SLTU:begin//smalelr than (unsingedd)
        ALU_outr=(R1<R2)?1'b1:1'b0;
        ALU_out_mr={1'b1,Rd};
        PSRr[3]=PSR[3];
        PSRr[2]=PSR[2];
        PSRr[1]=PSR[1];
        PSRr[0]=~ALU_outr[0];//no need for calc
    end
    OP_CMP:begin
        ALU_out_mr=5'b0;
        {PSRr[2],ALU_outr}=({1'b0,R1}+{1'b0,~R2}+1'b1);//2 is C
        PSRr[3]=((R1[31]!=R2[31])&&(ALU_outr[31] != R1[31]));//3 is OV
        PSRr[1]=ALU_outr[31];//1 is N
        PSRr[0]=(ALU_outr==0);//0 is Z
        notused=1;
    end

    //SHIFTS and rotates
    OP_SAR:begin//shift arthimetic right
        ALU_out_mr={1'b1,Rd};
        ALU_outr=$signed(R1)>>>R2[4:0];
        PSRr[3]=PSR[3];//3 is OV
        PSRr[1]=ALU_outr[31];//1 is N
        PSRr[0]=(ALU_outr==0);//0 is Z
        PSRr[2]=PSR[2];
    end
    OP_SHR:begin//shift logical right
        ALU_out_mr={1'b1,Rd};
        ALU_outr=R1>>R2[4:0];
        PSRr[3]=PSR[3];//3 is OV
        PSRr[1]=ALU_outr[31];//1 is N
        PSRr[0]=(ALU_outr==0);//0 is Z
        PSRr[2]=PSR[2];
    end
    OP_SHL:begin//shift logical left
        ALU_out_mr={1'b1,Rd};
        ALU_outr=R1<<R2[4:0];
        PSRr[3]=PSR[3];//3 is OV
        PSRr[1]=ALU_outr[31];//1 is N
        PSRr[0]=(ALU_outr==0);//0 is Z
        PSRr[2]=PSR[2];
    end
    OP_ROR:begin
        ALU_out_mr={1'b1,Rd};
        ALU_outr=(R1<<(32-R2[4:0])|R1>>R2[4:0]);
        PSRr[3]=PSR[3];//3 is OV
        PSRr[1]=ALU_outr[31];//1 is N
        PSRr[0]=(ALU_outr==0);//0 is Z
        PSRr[2]=PSR[2];
    end
    OP_ROL:begin
        ALU_out_mr={1'b1,Rd};
        ALU_outr=(R1<<(R2[4:0])|R1>>(32-R2[4:0]));
        PSRr[3]=PSR[3];//3 is OV
        PSRr[1]=ALU_outr[31];//1 is N
        PSRr[0]=(ALU_outr==0);//0 is Z
        PSRr[2]=PSR[2];
    end

    //JMPS and branches
    OP_JMP:begin
        flush=1;
        PC=IMM;
        ALU_outr=32'b0;
        ALU_out_mr=5'b0;
        PSRr[3]=PSR[3];
        PSRr[2]=PSR[2];
        PSRr[1]=PSR[1];
        PSRr[0]=PSR[0];
    end
    OP_JMP_IF:begin
        PC=(R1!=0)?IMM:0;
        flush=(R1!=0)?1:0;
        ALU_outr=32'b0;
        ALU_out_mr=5'b0;
        PSRr[3]=PSR[3];
        PSRr[2]=PSR[2];
        PSRr[1]=PSR[1];
        PSRr[0]=PSR[0];
    end
    OP_BLT:begin
        PC=(PSR[1]^PSR[3])?IMM:0;
        flush=(PSR[1]^PSR[3])?1:0;
        ALU_outr=32'b0;
        ALU_out_mr=5'b0;
        PSRr[3]=PSR[3];
        PSRr[2]=PSR[2];
        PSRr[1]=PSR[1];
        PSRr[0]=PSR[0];
    end
    OP_BGE:begin//resul is positive
        PC=(~(PSR[1]^PSR[3]))?IMM:0;
        flush=~(PSR[1]^PSR[3])?1:0;
        ALU_outr=32'b0;
        ALU_out_mr=5'b0;
        PSRr[3]=PSR[3];
        PSRr[2]=PSR[2];
        PSRr[1]=PSR[1];
        PSRr[0]=PSR[0];
    end
    OP_BEQ:begin
        PC=(PSR[0])?IMM:0;
        flush=(PSR[0])?1:0;
        ALU_outr=32'b0;
        ALU_out_mr=5'b0;
        PSRr[3]=PSR[3];
        PSRr[2]=PSR[2];
        PSRr[1]=PSR[1];
        PSRr[0]=PSR[0];
    end
    OP_BNE:begin
        PC=(~(PSR[0]))?IMM:0;
        flush=~(PSR[0])?1:0;
        ALU_outr=32'b0;
        ALU_out_mr=5'b0;
        PSRr[3]=PSR[3];
        PSRr[2]=PSR[2];
        PSRr[1]=PSR[1];
        PSRr[0]=PSR[0];
    end
    OP_BLTU:begin //This instr works with assumption of a Rs1-Rs2 or its equivalnet happened 
        PC=(~(PSR[2]))?IMM:0; ///unsigned Rs1-Rs2 gives C=1 no borrow so Rs1 bigger
        flush=~(PSR[2])?1:0;
        ALU_outr=32'b0;
        ALU_out_mr=5'b0;
        PSRr[3]=PSR[3];
        PSRr[2]=PSR[2];
        PSRr[1]=PSR[1];
        PSRr[0]=PSR[0];
    end
    OP_BGEU:begin //This instr works with assumption of a Rs1-Rs2 or its equivalnet happened 
        PC=(PSR[2])?IMM:0; ///unsigned Rs1-Rs2 gives C=1 no borrow so Rs1 bigger or equivalent
        flush=(PSR[2])?1:0;
        ALU_outr=32'b0;
        ALU_out_mr=5'b0;
        PSRr[3]=PSR[3];
        PSRr[2]=PSR[2];
        PSRr[1]=PSR[1];
        PSRr[0]=PSR[0];
    end
    OP_JMP_REG:begin
        PC=R1[11:0]; 
        flush=1;
        ALU_outr=32'b0;
        ALU_out_mr=5'b0;
        PSRr[3]=PSR[3];
        PSRr[2]=PSR[2];
        PSRr[1]=PSR[1];
        PSRr[0]=PSR[0];
    end
    OP_LUI:begin
        ALU_outr={IMM,20'b0};
        ALU_out_mr={1'b1,Rd};
        PSRr[3]=PSR[3];
        PSRr[2]=PSR[2];
        PSRr[1]=PSR[1];
        PSRr[0]=PSR[0];
    end
    OP_MOV:begin//no change on flags
        ALU_outr=R1;
        ALU_out_mr={1'b1,Rd};
        PSRr[3]=PSR[3];
        PSRr[2]=PSR[2];
        PSRr[1]=PSR[1];
        PSRr[0]=PSR[0];
    end
    OP_LOAD_IMM:begin//no change on flags
        ALU_outr={20'b0,IMM};
        ALU_out_mr={1'b1,Rd};
        PSRr[3]=PSR[3];
        PSRr[2]=PSR[2];
        PSRr[1]=PSR[1];
        PSRr[0]=PSR[0];
    end
    OP_HALT:begin
        done_from_calc=0;
        ALU_outr=0;
        ALU_out_mr=0;
        PSRr[3]=PSR[3];
        PSRr[2]=PSR[2];
        PSRr[1]=PSR[1];
        PSRr[0]=PSR[0];
        HALTr=1;
    end
    default:begin
        ALU_outr=0;
        ALU_out_mr=0;
        PSRr[3]=PSR[3];
        PSRr[2]=PSR[2];
        PSRr[1]=PSR[1];
        PSRr[0]=PSR[0];
    end

    endcase
end
assign  bitstart=MUL_state>DONE?0:5'(MUL_state[MUL_state_PARAM-1:0]<<SHIFT);



assign done=done_MEMr && done_from_calc;
//actual Rs calculation use ALU[1] and MEM's 
always@(*)begin
if(MEM_out_m=={1'b1,Rs1})
begin
    R1=MEM_out;
end
else if(ALU_out_m[1]=={1'b1,Rs1})
begin
    R1=ALU_out[1];
end
else if(ALU_out_m[0]=={1'b1,Rs1})begin
    R1=ALU_out[0];
end
else begin
    R1=R[Rs1];
end

if(MEM_out_m=={1'b1,Rs2})
begin
    R2=MEM_out;
end
else if(ALU_out_m[1]=={1'b1,Rs2})
begin
    R2=ALU_out[1];
end
else if(ALU_out_m[0]=={1'b1,Rs2})begin
    R2=ALU_out[0];
end
else begin
    R2=R[Rs2];
end

end


endmodule