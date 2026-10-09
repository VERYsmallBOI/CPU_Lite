module MEMProcess(
    input clk,
    input rst,
    output reg [31:0]MEM_out,   //hasto be registered 
    output reg [4:0]MEM_out_m,//hasto be registered
    input [7:0]OPC,
    input [3:0]Rd,
    input [3:0]Rs1,
    input [3:0]Rs2,
    input [11:0]IMM,
    input wire [31:0]R[15:0],//reg bank
    output reg done_MEMr,//comb
    //to and fro CAhce
    output reg [31:0]WDATA,//comb
    input [31:0]RDATA,
    output reg req_cache,//comb
    input cache_done,//just a pulse at end to when to sample values
    output reg [13:0] req_addr,//comb
    output reg write_cache//comb  1 is write 0 is read
    );
    //only done_MEM is used at forwarding_wait no place else not now its useless and is removed

//does load and store thats it 
//changes
//sneds 2 dones 1 registered and 1 combo mostly on off only on when Instrucciotn is runing
//both has no problem from WB(removed cos Regbank is in same LCK domain)
localparam OP_NOP       = 8'h00,
           OP_LOAD      = 8'h01,
           OP_LOAD_IND  = 8'h02,
           OP_STORE     = 8'h04,
           OP_STORE_IND = 8'h05;
reg State_MEMr,State_MEM;

localparam STARTER=0,
    ONGOING=1;
reg sample_MEM;//when read operation 
always@(posedge clk or negedge rst)begin
    if(~rst)begin
        MEM_out<=0;
        MEM_out_m<=0;//invliad so no worries
        State_MEM<=STARTER;
    end
else begin
State_MEM<=State_MEMr;
if(sample_MEM)begin
    MEM_out<=RDATA;
    MEM_out_m<={1'b1,Rd};
end
end
end

//State machine 
//checks opcode when No outstanding tranaction 
/*fillout  sample_MEM 
done_MEMr and
 WDATA 
 req_cache 
 req-addr 
 write_cache 
State_MEMr
*/
always@(*)begin

//remain same
case(OPC)
    OP_NOP:begin
        WDATA=0;
        req_addr=0; 
        write_cache=0;
    end
    OP_LOAD:begin//read so no WDATA
        WDATA=0;
        req_addr={2'b0,IMM};//12bit
        write_cache=0;
    end
    OP_LOAD_IND:begin
        WDATA=0;
        req_addr=R[Rs1][13:0];//14bit
        write_cache=0;//read
    end
    OP_STORE:begin
        WDATA=R[Rd];
        req_addr={2'b0,IMM};//14bit
        write_cache=1;//wiret
    end
OP_STORE_IND:begin

        WDATA=R[Rd];
        req_addr=R[Rs2][13:0];//14bit
        write_cache=1;//wiret

end
    default:begin //other instructions with EX done  //not possible but doing this so same logic is synthesized for both
        WDATA=0;
        req_addr=0;
        write_cache=0;//read
        //same as OP_NOP
    end

    endcase
end

always@(*)begin
case(State_MEM)

STARTER:begin
    sample_MEM=0;//as no value present here 
    case(OPC)
    OP_NOP:begin
        done_MEMr=1;
        req_cache=0;
        State_MEMr=STARTER;
    end
    OP_LOAD:begin//read so no WDATA
        done_MEMr=0;
        req_cache=1;
        State_MEMr=ONGOING;
    end
    OP_LOAD_IND:begin
        done_MEMr=0;
        req_cache=1;
        State_MEMr=ONGOING;
    end
    OP_STORE:begin
        done_MEMr=0;
        req_cache=1;
        State_MEMr=ONGOING;
    end
OP_STORE_IND:begin

        done_MEMr=0;
        req_cache=1;
        State_MEMr=ONGOING;

end
    default:begin //other instructions with EX done 
        done_MEMr=1;
        req_cache=0;
        State_MEMr=STARTER;
        //same as OP_NOP
    end

    endcase

end

ONGOING:begin
    req_cache=~cache_done;//if done go back to 0 else stay 1       
    //values on others shoudl be stable until they leave here 
    sample_MEM=cache_done&&((OPC==OP_LOAD)||(OPC==OP_LOAD_IND));//if cache is done then get the value
    done_MEMr=cache_done;
    State_MEMr=done_MEMr?STARTER:ONGOING;//if done go to STARTER (accept new starts)
end

default:begin
        done_MEMr=1;
        req_cache=0;
        State_MEMr=STARTER;
end
endcase



end


endmodule