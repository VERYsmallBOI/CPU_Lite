///send data 3 2 1 0
///catch it 3 2 1 0
module DATAMEM(
    input dclk,//dataMEM clk
    input drst,

    //rec FIFO
    output reg wrcmd_r,
    output reg [47:0]WRDATA_rFIFO,
    input full_r,

    //send FIFO 
    input [47:0]RDATA_sFIFO,
    output reg rcmd_s,
    input empty_s
);

reg [2:0] State_DM,State_DMr;
reg [1:0]datacounter,datacounterr;
localparam EMPTY      = 3'd0,
           CHECK      = 3'd1,
           FETCH      = 3'd2,
           GIVE       = 3'd3,
           COLLECT    = 3'd4,
           WRITE_SRAM = 3'd5,
           ACK        = 3'd6;
//fetch->read_sram->Give
//collect->Write_sram->ACk    

//DATAMEM instantation 8 x [512][128]
reg [13:0]ADDR;

parameter OFF=2'b10,
          TOREAD=2'b10,
          TOWRITE=2'b00;
reg [1:0]DM_grped;
wire WEB_DM,OEB_DM;
assign {WEB_DM,OEB_DM}=DM_grped;

reg [7:0]CS_select;//based on first 3 bits of Current_Addr
wire [127:0]RDATA_DM[0:7];
reg [127:0]WRDATA_DM;

//DATAMEM will store lines instead of words


reg [127:0]SAVE_READ,SAVE_READr;
reg sample_SAVE;
reg [13:2]Current_Addr,Current_Addr_r;//current operation addr
reg sample_CA;
//CS_select logic pengin its and of addr part slects  and csb from DM_grpied


//Sender FIFO template for cmd and data
//FETCH ==> 1'b1 35'b0 12'b req_addr[13:2](line addr)
//DATA ==> 1'b0 1'b1 14'b(word addr for STORE_DATA its old data so old tag + index_current+datacounter) 32b data 
//Nothing will obv be 48'b0 so no 1 to reduce power in B.S.
//so it is neccesary make the value differ from nohting

///reciever FIFO template for data and ack
//ACK ==> 2'b01 34'b0 12'b req_addr[13:2](line addr)
//DATA ==> 2'b10 14'b req_addr[13:0](word addr) 32bit data

//State logic pending

//stuff to change
//sample_CA;-- sample current address
//Current_Addr_r --what to sample as addr
//SAVE_READr -- save read given by sram on read/read given by sFIFO
//sample_SAVE -- when to save op of sram/sFIFO
//DM_grped -- DM sram controls 
//CS_select -- gives clb to each sram note active low
//rcmd_s --  to pop
//WRDATA_rFIFO -- what ot write to FIFOr
//wrcmd_r -- to write  ot fifo
//WRDATA_DM -- what to write to DM sram
always@(*)begin
    //defeautls
    DM_grped=OFF;
    Current_Addr_r=0;
    SAVE_READr=0;
    sample_SAVE=0;
    CS_select='1;
    wrcmd_r=0;
    WRDATA_rFIFO=0;
    WRDATA_DM=0;
    sample_CA=0;
    rcmd_s=0;
    case(State_DM)
    EMPTY:begin
        if(empty_s)begin
            State_DMr=EMPTY;
            datacounterr=0;
        end
        else begin
            State_DMr=CHECK;
            datacounterr=3;//next will need it
        end
               
    end
    CHECK:begin
        case(RDATA_sFIFO[47:46])
        2'b01:begin
            //DATA
            //this will be 3 so add to SAVE_READr by shifting 32 btis each
            sample_SAVE=1;
            SAVE_READr={96'd0,RDATA_sFIFO[31:0]};//clears prevoius value
            sample_CA=1;
            Current_Addr_r=RDATA_sFIFO[45:34];
            datacounterr=RDATA_sFIFO[33:32];
            State_DMr=COLLECT;

        end
        2'b10:begin
            //FETCH
            State_DMr=FETCH;
            datacounterr=0;
            sample_CA=1;
            Current_Addr_r=RDATA_sFIFO[11:0];//last 12 bits
        end
        default:begin
            //invalid maybe write side had glitches has to be cleared
            State_DMr=empty_s?EMPTY:CHECK;
            datacounterr=0;
        end
        endcase
        rcmd_s=1;//has to be be careful as write side may not havce finished
    end
    FETCH:begin
            if(datacounter==0)begin//read from sram cmd
                datacounterr=datacounter+1;
                //change DM_grped and CS_slect 
                DM_grped=TOREAD;
                CS_select=~(8'b1<<Current_Addr[13:11]);
                State_DMr=FETCH;
            end
            else begin//read 
                datacounterr=3;
                State_DMr=GIVE;
                SAVE_READr=RDATA_DM[Current_Addr[13:11]];//0 to 7 select
                sample_SAVE=1;
            end
    end
    GIVE:begin//givre in 4 cycles first 3 2 1 0 last
        if(~full_r)
        begin
                wrcmd_r=1;
                
        case(datacounter)//array select here will be a nightmamre to do with in linting
            2'b00:begin//go back to cechking
                State_DMr=EMPTY;
                datacounterr=0;
                WRDATA_rFIFO={2'b10,Current_Addr,datacounter,SAVE_READ[31:0]};
            end
            2'b01:begin
                State_DMr=GIVE;
                datacounterr=0;
                WRDATA_rFIFO={2'b10,Current_Addr,datacounter,SAVE_READ[63:32]};
            end
            2'b10:begin
                State_DMr=GIVE;
                datacounterr=1;
                WRDATA_rFIFO={2'b10,Current_Addr,datacounter,SAVE_READ[95:64]};
            end
            2'b11:begin
                State_DMr=GIVE;
                datacounterr=2;
                WRDATA_rFIFO={2'b10,Current_Addr,datacounter,SAVE_READ[127:96]};
            end
            default:begin
                State_DMr=EMPTY;
                datacounterr=0;
                WRDATA_rFIFO={2'b10,Current_Addr,datacounter,SAVE_READ[31:0]};
            end
        endcase
        end
        else begin
            State_DMr=GIVE;
            datacounterr=datacounter;
        end
    end
    COLLECT:begin//read the value here then go to ack to give ack
        //needed address in Current_Addr
        if(~empty_s)begin
            datacounterr=RDATA_sFIFO[33:32];
            if(datacounterr==0)begin
                State_DMr=WRITE_SRAM;
                //data is not safe yet so do sram data write there when stabel
            end
            else begin
                State_DMr=COLLECT;
            end
            rcmd_s=1;
            sample_SAVE=1;
            SAVE_READr=128'(SAVE_READ<<32)|{96'd0,RDATA_sFIFO[31:0]};
        end
        else begin//writer is kinda slow and hasnt finisneded
            State_DMr=COLLECT;//this can lead to deadlock check once more
            datacounterr=datacounter;
        end
    end
    WRITE_SRAM:begin
        if(datacounter==0)begin//write here
            datacounterr=datacounter+1;
            //change DM_grped and CS_slect 
            DM_grped=TOWRITE;
            CS_select=~(8'b1<<Current_Addr[13:11]);
            WRDATA_DM=SAVE_READ;
            State_DMr=WRITE_SRAM;
        end
        else begin//jump here to ACK 
            datacounterr=0;
            State_DMr=ACK;
        end

    end
    ACK:begin
        if(~full_r)begin//give acck
            wrcmd_r=1;
            State_DMr=EMPTY;
            datacounterr=0;
            WRDATA_rFIFO={2'b01,34'b0,Current_Addr};
        end
        else begin//stay here until then
        State_DMr=ACK;
        datacounterr=0;
        end
    end
    default:begin
        State_DMr=EMPTY;
        datacounterr=0;

    end
    endcase

    end



//save values here
always@(posedge dclk or negedge drst)begin
    if(~drst)begin
        State_DM<=0;
         SAVE_READ<=0;
         datacounter<=0;
         Current_Addr<=0;
    end
    else begin
        if(sample_SAVE)begin
            SAVE_READ<=SAVE_READr;
        end
        State_DM<=State_DMr;
        datacounter<=datacounterr;
        if(sample_CA)begin
            Current_Addr<=Current_Addr_r;
        end
    end
end


genvar i;
generate
    for(i = 0; i < 8; i = i + 1) begin : module_array
        SRAM1RW512x128 DATAMEM(.A(Current_Addr[10:2]),.CE(dclk),.WEB(WEB_DM),.OEB(OEB_DM),.CSB(CS_select[i]),.I(WRDATA_DM),.O(RDATA_DM[i]));
    end
endgenerate

endmodule