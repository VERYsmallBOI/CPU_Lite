//for mul use done as uniqueness if another mul comes in so with done clear the State/no of flags assoctiated.

module ALUProcess(
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

//MEM and ALU process clears the current(0)their own outs only if they have nothing to give
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

//can do work without done fomr MEM but cant push to reg until that 
//produces ALU outs and it meta does all the ALU calcs(MUL ADD OR etc)
//MUL uses 
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

//MUL
reg [2:0]MUL_state,MUL_stater;//4 state 8 pp at once 4 states(0 to 3 MAC in4 wait)
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
//when it actually finishes afeter forwarding go back to 0 so if next EX is also MUL doesnt fuck it up
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
    MUL_stater=0;//only change is at MUL dont let it move in 3 state unless done comes 
    done_from_calc=1;//no latency execpt for mul 
    PP=0;
    notused=0;//CMP JMP Branch 
    flush=0;//JMP Branch (CALL RET -- pending)
    PC=0;//has to be sent combo to flush
    case(OPC)
    ADD:begin
        ALU_out_mr={1'b1,Rd};
        {PSRr[2],ALU_outr}={1'b0,R1}+{1'b0,R2};//2 is C
        PSRr[3]=((R1[31]==R2[31])&&(ALU_outr[31] != R1[31]));//3 is OV
        PSRr[1]=ALU_outr[31];//1 is N
        PSRr[0]=(ALU_outr==0);//0 is Z
    end
    SUB:begin
        ALU_out_mr={1'b1,Rd};
        {PSRr[2],ALU_outr}={1'b0,R1}+{1'b0,~R2}+1'b1;//2 is C
        PSRr[3]=((R1[31]!=R2[31])&&(ALU_outr[31] != R1[31]));//3 is OV
        PSRr[1]=ALU_outr[31];//1 is N
        PSRr[0]=(ALU_outr==0);//0 is Z
    end
    ADDI:begin
        ALU_out_mr={1'b1,Rd};
        {PSRr[2],ALU_outr}={1'b0,R1}+{1'b0,{20{IMM[11]}},IMM};//2 is C Sign exxtension for IMM is needed as per spec
        PSRr[3]=((R1[31]==IMM[11])&&(ALU_outr[31] != R1[31]));//3 is OV
        PSRr[1]=ALU_outr[31];//1 is N
        PSRr[0]=(ALU_outr==0);//0 is Z
    end
    SUBI:begin
        ALU_out_mr={1'b1,Rd};
        {PSRr[2],ALU_outr}={1'b0,R1}+{1'b0,~{{20{IMM[11]}},IMM}}+1'b1;//2 is C
        PSRr[3]=((R1[31]!=IMM[11])&&(ALU_outr[31] != R1[31]));//3 is OV
        PSRr[1]=ALU_outr[31];//1 is N
        PSRr[0]=(ALU_outr==0);//0 is Z
    end
    MUL:begin
        ALU_out_mr={1'b1,Rd};
        done_from_calc=(MUL_state>2);
        MUL_stater=(MUL_state[2])?4:MUL_state+1; //MUL_state[2] is 4 to 7 tho we will be using only til 4
        PP=(MUL_state[2])?0:R1*R2[(MUL_state[1:0]<<3)+:8];//adds inactiveness and safegaurd
        ACCr=(MUL_state[2])?ACC:(PP<<(MUL_state<<3))+ACC;//do 0 to 7 8 to 15 16 to 23 24 to 31 pp in order and shift pp and add to ACC 
        ALU_outr=(MUL_state>2)?ACCr:0;
        PSRr[3]=PSR[3];//3 is OV
        PSRr[1]=(MUL_state>2)?ALU_outr[31]:PSR[1];//1 is N
        PSRr[0]=(MUL_state>2)?(ALU_outr==0):PSR[0];//0 is Z
        PSRr[2]=PSR[2];
    end
    AND:begin
        ALU_out_mr={1'b1,Rd};
        ALU_outr=R1&R2;
        PSRr[3]=PSR[3];//3 is OV
        PSRr[1]=ALU_outr[31];//1 is N
        PSRr[0]=(ALU_outr==0);//0 is Z
        PSRr[2]=PSR[2];
    end
    OR:begin
        ALU_out_mr={1'b1,Rd};
        ALU_outr=R1|R2;
        PSRr[3]=PSR[3];//3 is OV
        PSRr[1]=ALU_outr[31];//1 is N
        PSRr[0]=(ALU_outr==0);//0 is Z
        PSRr[2]=PSR[2];
    end
    NOT:begin
        ALU_out_mr={1'b1,Rd};
        ALU_outr=~R1;
        PSRr[3]=PSR[3];//3 is OV
        PSRr[1]=ALU_outr[31];//1 is N
        PSRr[0]=(ALU_outr==0);//0 is Z
        PSRr[2]=PSR[2];
    end
    XOR:begin
        ALU_out_mr={1'b1,Rd};
        ALU_outr=R1^R2;
        PSRr[3]=PSR[3];//3 is OV
        PSRr[1]=ALU_outr[31];//1 is N
        PSRr[0]=(ALU_outr==0);//0 is Z
        PSRr[2]=PSR[2];
    end
    ANDI:begin
        ALU_out_mr={1'b1,Rd};
        ALU_outr=R1&({20'b0,IMM});//can also be {R1[31:12],IMM^R1[11:0]} but dont want to confuse
        PSRr[3]=PSR[3];//3 is OV
        PSRr[1]=ALU_outr[31];//1 is N
        PSRr[0]=(ALU_outr==0);//0 is Z
        PSRr[2]=PSR[2];
    end
    ORI:begin
        ALU_out_mr={1'b1,Rd};
        ALU_outr=R1|({20'b0,IMM});//can also be {R1[31:12],IMM^R1[11:0]} but dont want to confuse
        PSRr[3]=PSR[3];//3 is OV
        PSRr[1]=ALU_outr[31];//1 is N
        PSRr[0]=(ALU_outr==0);//0 is Z
        PSRr[2]=PSR[2];
    end
    XORI:begin
        ALU_out_mr={1'b1,Rd};
        ALU_outr=R1^({20'b0,IMM});//can also be {R1[31:12],IMM^R1[11:0]} but dont want to confuse
        PSRr[3]=PSR[3];//3 is OV
        PSRr[1]=ALU_outr[31];//1 is N
        PSRr[0]=(ALU_outr==0);//0 is Z
        PSRr[2]=PSR[2];
    end
    ///comparisions
    EQ:begin
        ALU_out_mr=5'b0;
        ALU_outr=(R1==R2);
        PSRr[3]=PSR[3];//3 is OV
        PSRr[1]=PSR[1];//1 is N
        PSRr[0]=~ALU_outr[0];//0 is Z
        PSRr[2]=PSR[2];
    end
    SLT:begin//smalelr than (singedd)
        ALU_outr=($signed(R1)<$signed(R2))?1'b1:1'b0;
        ALU_out_mr={1'b1,Rd};
        PSRr[3]=PSR[3];
        PSRr[2]=PSR[2];
        PSRr[1]=PSR[1];
        PSRr[0]=~ALU_outr[0];//no need for calc
    end
    SLTU:begin//smalelr than (unsingedd)
        ALU_outr=(R1<R2)?1'b1:1'b0;
        ALU_out_mr={1'b1,Rd};
        PSRr[3]=PSR[3];
        PSRr[2]=PSR[2];
        PSRr[1]=PSR[1];
        PSRr[0]=~ALU_outr[0];//no need for calc
    end
    CMP:begin
        ALU_out_mr=5'b0;
        {PSRr[2],ALU_outr}=({1'b0,R1}+{1'b0,~R2}+1'b1);//2 is C
        PSRr[3]=((R1[31]!=R2[31])&&(ALU_outr[31] != R1[31]));//3 is OV
        PSRr[1]=ALU_outr[31];//1 is N
        PSRr[0]=(ALU_outr==0);//0 is Z
        notused=1;
    end

    //SHIFTS and rotates
    SAR:begin//shift arthimetic right
        ALU_out_mr={1'b1,Rd};
        ALU_outr=$signed(R1)>>>R2[4:0];
        PSRr[3]=PSR[3];//3 is OV
        PSRr[1]=ALU_outr[31];//1 is N
        PSRr[0]=(ALU_outr==0);//0 is Z
        PSRr[2]=PSR[2];
    end
    SHR:begin//shift logical right
        ALU_out_mr={1'b1,Rd};
        ALU_outr=R1>>R2[4:0];
        PSRr[3]=PSR[3];//3 is OV
        PSRr[1]=ALU_outr[31];//1 is N
        PSRr[0]=(ALU_outr==0);//0 is Z
        PSRr[2]=PSR[2];
    end
    SHL:begin//shift logical left
        ALU_out_mr={1'b1,Rd};
        ALU_outr=R1<<R2[4:0];
        PSRr[3]=PSR[3];//3 is OV
        PSRr[1]=ALU_outr[31];//1 is N
        PSRr[0]=(ALU_outr==0);//0 is Z
        PSRr[2]=PSR[2];
    end
    ROR:begin
        ALU_out_mr={1'b1,Rd};
        ALU_outr=(R1<<(32-R2[4:0])|R1>>R2[4:0]);
        PSRr[3]=PSR[3];//3 is OV
        PSRr[1]=ALU_outr[31];//1 is N
        PSRr[0]=(ALU_outr==0);//0 is Z
        PSRr[2]=PSR[2];
    end
    ROL:begin
        ALU_out_mr={1'b1,Rd};
        ALU_outr=(R1<<(R2[4:0])|R1>>(32-R2[4:0]));
        PSRr[3]=PSR[3];//3 is OV
        PSRr[1]=ALU_outr[31];//1 is N
        PSRr[0]=(ALU_outr==0);//0 is Z
        PSRr[2]=PSR[2];
    end

    //JMPS and branches
    JMP:begin
        flush=1;
        PC=IMM;
        ALU_outr=32'b0;
        ALU_out_mr=5'b0;
        PSRr[3]=PSR[3];
        PSRr[2]=PSR[2];
        PSRr[1]=PSR[1];
        PSRr[0]=PSR[0];
    end
    JMP_IF:begin
        PC=(R1!=0)?IMM:0;
        flush=(R1!=0)?1:0;
        ALU_outr=32'b0;
        ALU_out_mr=5'b0;
        PSRr[3]=PSR[3];
        PSRr[2]=PSR[2];
        PSRr[1]=PSR[1];
        PSRr[0]=PSR[0];
    end
    BLT:begin
        PC=(PSR[1]^PSR[3])?IMM:0;
        flush=(PSR[1]^PSR[3])?1:0;
        ALU_outr=32'b0;
        ALU_out_mr=5'b0;
        PSRr[3]=PSR[3];
        PSRr[2]=PSR[2];
        PSRr[1]=PSR[1];
        PSRr[0]=PSR[0];
    end
    BGE:begin//resul is positive
        PC=(~(PSR[1]^PSR[3]))?IMM:0;
        flush=~(PSR[1]^PSR[3])?1:0;
        ALU_outr=32'b0;
        ALU_out_mr=5'b0;
        PSRr[3]=PSR[3];
        PSRr[2]=PSR[2];
        PSRr[1]=PSR[1];
        PSRr[0]=PSR[0];
    end
    BEQ:begin
        PC=(PSR[0])?IMM:0;
        flush=(PSR[0])?1:0;
        ALU_outr=32'b0;
        ALU_out_mr=5'b0;
        PSRr[3]=PSR[3];
        PSRr[2]=PSR[2];
        PSRr[1]=PSR[1];
        PSRr[0]=PSR[0];
    end
    BNE:begin
        PC=(~(PSR[0]))?IMM:0;
        flush=~(PSR[0])?1:0;
        ALU_outr=32'b0;
        ALU_out_mr=5'b0;
        PSRr[3]=PSR[3];
        PSRr[2]=PSR[2];
        PSRr[1]=PSR[1];
        PSRr[0]=PSR[0];
    end
    BLTU:begin //This instr works with assumption of a Rs1-Rs2 or its equivalnet happened 
        PC=(~(PSR[2]))?IMM:0; ///unsigned Rs1-Rs2 gives C=1 no borrow so Rs1 bigger
        flush=~(PSR[2])?1:0;
        ALU_outr=32'b0;
        ALU_out_mr=5'b0;
        PSRr[3]=PSR[3];
        PSRr[2]=PSR[2];
        PSRr[1]=PSR[1];
        PSRr[0]=PSR[0];
    end
    BGEU:begin //This instr works with assumption of a Rs1-Rs2 or its equivalnet happened 
        PC=(PSR[2])?IMM:0; ///unsigned Rs1-Rs2 gives C=1 no borrow so Rs1 bigger or equivalent
        flush=(PSR[2])?1:0;
        ALU_outr=32'b0;
        ALU_out_mr=5'b0;
        PSRr[3]=PSR[3];
        PSRr[2]=PSR[2];
        PSRr[1]=PSR[1];
        PSRr[0]=PSR[0];
    end
    JMP_REG:begin
        PC=R1[11:0]; 
        flush=1;
        ALU_outr=32'b0;
        ALU_out_mr=5'b0;
        PSRr[3]=PSR[3];
        PSRr[2]=PSR[2];
        PSRr[1]=PSR[1];
        PSRr[0]=PSR[0];
    end
    LUI:begin
        ALU_outr={IMM,20'b0};
        ALU_out_mr={1'b1,Rd};
        PSRr[3]=PSR[3];
        PSRr[2]=PSR[2];
        PSRr[1]=PSR[1];
        PSRr[0]=PSR[0];
    end
    MOV:begin//no change on flags
        ALU_outr=R1;
        ALU_out_mr={1'b1,Rd};
        PSRr[3]=PSR[3];
        PSRr[2]=PSR[2];
        PSRr[1]=PSR[1];
        PSRr[0]=PSR[0];
    end
    LOAD_IMM:begin//no change on flags
        ALU_outr={20'b0,IMM};
        ALU_out_mr={1'b1,Rd};
        PSRr[3]=PSR[3];
        PSRr[2]=PSR[2];
        PSRr[1]=PSR[1];
        PSRr[0]=PSR[0];
    end
    HALT:begin
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