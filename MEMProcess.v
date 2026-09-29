module MEMprocess(
    
    output reg [31:0]MEM_out,    
    output reg [4:0]MEM_out_m,
    input [7:0]OPC,
    input [3:0]Rd,
    input [3:0]Rs1,
    input [3:0]Rs2,
    input [11:0]IMM,

    );
    //only done_MEM is used at forwarding_wait no place else

//does load and store thats it 
//changes
//sneds 2 dones 1 registered and 1 combo mostly on off only on when Instrucciotn is runing
//both has no problem from WB(removed cos Regbank is in same LCK domain)
always@(posedge clk or negedge rst)begin


end


endmodule