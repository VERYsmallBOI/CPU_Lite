module FIFO(wclk,rclk,wrst,rrst,empty,full,wdata,rdata,rcmd,wcmd);
//pahse bit implementation.
//instead of sending the whole ptr send change (change indicates +1) and make canclk(write side)by change a bit and sync that onyl and get it to this side(read) only if the change is 1 wil it change to new read ptr vallue
input wclk,rclk,wrst,rrst,rcmd,wcmd;
input [98:0]wdata;
reg[4:0]rptr,wptr;
output reg [98:0]rdata;
reg [98:0]FIFOMEM[15:0];//16 messages
reg [4:0]wptrr,rptrr;
wire [4:0]wptrg,rptrg,wptrgs,rptrgs;
output reg empty;
output reg full;
reg [4:0]wptrgr,rptrgr;
//reset syncs
//for wrst
reg wrstsync1,wrstsync2;
always@(posedge wclk or negedge wrst)begin
    if(~wrst)begin
        wrstsync1<=0;
        wrstsync2<=0;
    end
    else begin
        wrstsync1<=1;
        wrstsync2<=wrstsync1;
    end
end

//for rrst
reg rrstsync1,rrstsync2;
always@(posedge rclk or negedge rrst)begin
    if(~rrst)begin
        rrstsync1<=0;
        rrstsync2<=0;
    end
    else begin
        rrstsync1<=1;
        rrstsync2<=rrstsync1;
    end
end

//write
always@(posedge wclk,negedge wrst)begin
    if(~wrst)begin
        wptr<=0;
        wptrgr<=0;
    end
    else begin
    wptr<=wptrr;
    wptrgr<=wptrg;
    end
end
always@(posedge wclk)begin
    if(~full&&wcmd)begin
    FIFOMEM[wptr[3:0]]<=wdata;
    end
end

always@(*)begin
    if(wcmd&&~full)begin
        wptrr=wptr+1;
    end
    else begin
        wptrr=wptr;
    end
end
always@(*)begin
if({~wptrg[4],~wptrg[3],wptrg[2:0]}=={rptrgs})begin
    full=1;
end
else begin
    full=0;
end
end

//read
always@(posedge rclk,negedge rrst)begin
    if(~rrst)begin
        rptr<=0;
        rdata<=0;
        rptrgr<=0;
    end
    else begin
        rptr<=rptrr;
        rptrgr<=rptrg;
    if(~empty)begin
        rdata<=FIFOMEM[rptr[3:0]];
    end
    end
end

always@(*)begin
    if(rcmd&&~empty)begin
        rptrr=rptr+1;
    end
    else begin
        rptrr=rptr;
    end
end
always@(*)begin
if(rptrg==wptrgs)begin
    empty=1;
end
else begin
    empty=0;
end
end




b2g gw(.in1(wptr),.out1(wptrg));
b2g gr(.in1(rptr),.out1(rptrg));

TFF twowrite0(.D(wptrgr[0]),.rst(rrstsync2),.clk(rclk),.q(wptrgs[0]));
TFF twowrite1(.D(wptrgr[1]),.rst(rrstsync2),.clk(rclk),.q(wptrgs[1]));
TFF twowrite2(.D(wptrgr[2]),.rst(rrstsync2),.clk(rclk),.q(wptrgs[2]));
TFF twowrite3(.D(wptrgr[3]),.rst(rrstsync2),.clk(rclk),.q(wptrgs[3]));
TFF twowrite4(.D(wptrgr[4]),.rst(rrstsync2),.clk(rclk),.q(wptrgs[4]));


TFF tworead0(.D(rptrgr[0]),.rst(wrstsync2),.clk(wclk),.q(rptrgs[0]));
TFF tworead1(.D(rptrgr[1]),.rst(wrstsync2),.clk(wclk),.q(rptrgs[1]));
TFF tworead2(.D(rptrgr[2]),.rst(wrstsync2),.clk(wclk),.q(rptrgs[2]));
TFF tworead3(.D(rptrgr[3]),.rst(wrstsync2),.clk(wclk),.q(rptrgs[3]));
TFF tworead4(.D(rptrgr[4]),.rst(wrstsync2),.clk(wclk),.q(rptrgs[4]));



endmodule


module b2g(in1,out1);
input [4:0]in1;
output reg [4:0]out1;

always@(*)begin
out1=in1^{1'b0,in1[4:1]};
end
endmodule

module TFF(D,rst,clk,q);
input D,rst,clk;
wire q1;
output q;
dff d1(D,rst,clk,q1);
dff d2(q1,rst,clk,q);

endmodule

module dff(D,rst,clk,q);
input D,rst,clk;
output reg q;


always@(posedge clk,negedge rst)begin

    if(!rst)begin
        q<=0;
    end
    else q<=D;

end

endmodule