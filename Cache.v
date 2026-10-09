//boht FIFO will use a 32x48 mem 
//33rd bit in Sender FIFO is 1 for any req or data snet
//in reciver FIFO (ACK case =0 on 39th bit) all the other bits are 1s
//cache will follow send and check mechanism 
//datamem just replies
//data is sent in 4 cycles sent by 0(last) 1 2 3(first)
//data is recieved in 4 cycles 3 first 2 1 0 last
module Cache(input clk,
input rst,
//to and fro MEMprocess
input [13:0]req_addr,
input write,
input [31:0]WDATA,
output reg [31:0]RDATA,
input req_CPU,
output reg done,
//sender fifo
output reg s_wrcmd,
input s_fifo_full,
output reg [47:0]s_wdata,
//reciever fifo
output reg r_rcmd,
input r_empty,
input [47:0]r_rdata
);
reg ACK;//used for ACK gen
//req 0 to 1 and cache starts working and done 0 to 1 and req 1 to 0 then done 1 to 0
//reg [127:0][127:0]data;
//data in CACHE will follow 3 2 1 0 of words in a liine

wire [7:0]Tagoutput;


//CM - cachemem single port sram 2x64x128 cache for data and 1x128x8 for tag
//TagCM for tag holder of cache memory
wire [5:0]addr_to_CM;//6 bit addr set index's 6 bit LSB MSB is for selecting which cache
wire [6:0]addr_to_TCM;
wire [127:0]rdata_from_CM0;//0 cache
wire [127:0]rdata_from_CM1;
reg [127:0]wdata_to_CM0;//0 cache
reg [127:0]wdata_to_CM1;
wire [4:0]tag_from_TCM;//read on TCM
reg [4:0]tag_to_TCM;//write on TCM
wire WEB_CM0;
wire WEB_CM1;
wire WEB_TagCM;
wire OEB_CM1;
wire OEB_CM0;
wire OEB_TagCM;
wire CSB_CM0;
wire CSB_CM1;
wire CSB_TagCM;

wire [4:0] tag;
wire [6:0] index;
wire [1:0] offset;
assign {tag,index,offset}=req_addr;
reg sampleTags,sampledatas;
reg [127:0]sampledata;
reg [4:0]sampleTag;
assign tag_from_TCM=Tagoutput[4:0];
assign addr_to_CM=index[5:0];//remvoed last 2 bits (offset)
assign addr_to_TCM=index;//indicates set index part

wire CM_select;
assign CM_select=index[6];

reg [2:0] TagCM_grped,CM0_grped,CM1_grped;
assign {CSB_CM0,WEB_CM0,OEB_CM0}=CM0_grped;
assign {CSB_TagCM, WEB_TagCM, OEB_TagCM} = TagCM_grped;
assign {CSB_CM1, WEB_CM1, OEB_CM1} = CM1_grped;
parameter OFF=3'b110,
          TOREAD=3'b010,
          TOWRITE=3'b000;
//these two has to be made with FFs
reg [127:0]valid;
reg [127:0]dirty;
//State 
localparam NOREQ = 4'd0,
CHECK=4'd1,//checks valid and tag for hit or miss  
WRITE=4'd2,//writes to valid memory and gives done
READ=4'd3,//reads a valid hit memory and sends result and done
STORE_DATA=4'd4,//Send data 00 to 11(3)
STORE_ACK=4'd5,//recieve ACK and change the dirty bit of the value associated to 0
FETCH_CMD=4'd6,
FETCH_READ=4'd7,
FETCH_WRITE=4'd8;//make values in cache updaeteed and its meta too; when read it gives the fetched value and when write 
//for reading the Values fetch get it reads 00 to 11(3)
reg [3:0]State,Stater;
reg [1:0]data_counter,data_counterr;//goes 0 to 3 
reg [127:0]Fetched_data,Fetched_datar;
reg Fetchsample;

//NOREQ->CHECK->HIT->WRite or READ 
//MISS 
//WRITE valid is 0 just FETCH_CMD -> FETCH_READ -> FETCH_WRITE
//valid is 1 dirty is 0  (tag not match)   FETCH_CMD -> FETCH_READ -> FETCH_WRITE(just write with updated value)
//valid is 1 dirty is 1 (tag not match)  (have to read the data 1st done in CHECK) STORE_DATA(old value) -> STORE_ACK -> FETCH_CMD(new value) ->FETCH_READ -> FETCH_WRITE
//READ valid is 0 just FETCH_CMD -> FETCH_READ -> FETCH_WRITE
//valid is 1 dirty is 0(tag not match)   FETCH_CMD -> FETCH_READ -> FETCH_WRITE
//valid is 1 dirty is 1(tag not match)  (have to read the data 1st) STORE_DATA(old value) -> STORE_ACK -> FETCH_CMD(new value) ->FETCH_READ -> FETCH_WRITE



//Sender FIFO template for cmd and data
//FETCH ==> 1'b1 35'b0 12'b req_addr[13:2](line addr)
//DATA ==> 1'b0 1'b1 12'b(word addr for STORE_DATA its old data so old tag + index_current+datacounter) 32b data 
//Nothing will obv be 48'b0 so no 1 to reduce power in B.S.
//so it is neccesary make the value differ from nohting

///reciever FIFO template for data and ack
//ACK ==> 2'b01 34'b0 12'b req_addr[13:2](line addr)
//DATA ==> 2'b10 14'b req_addr[13:0](word addr) 32bit data

reg validupdate,dirtyupdate;
always@(posedge clk , negedge rst)begin
    if(~rst)begin
        valid<=0;
        dirty<=0;
    end
    else begin
        //at fetch_read end make corresponding valid to 1 and dirty to 0 
        //at write make corresponding dirty to 1 (no change in valid)
        if(validupdate)begin
            valid[index]<=1;
        end
        if(dirtyupdate)begin
            dirty[index]<=write||(dirty[index]);//if write is 1 it writes dirty and read nothing changes
        end

    end
end



always @(posedge clk, negedge rst) begin
    if(!rst)
    begin
        State<=0;
        data_counter<=0;
        sampleTag<=0;
        sampledata<=0;
        Fetched_data<=0;
    end
    else begin
    data_counter<=data_counterr;
    State<=Stater;
    
    Fetched_data<=Fetchsample?Fetched_datar:Fetched_data;//seeing how any data is wrong out of window clearing has no use
//tag can be variable context one is already stored in Tag Ram and one is given/requested by CPU
    sampleTag<=sampleTags?tag_from_TCM:sampleTag;
    
    if(sampledatas)begin
        if(CM_select)
            sampledata<=rdata_from_CM1;
            else sampledata<=rdata_from_CM0;
    end
    end

end


//drive done signal and drive r_rcmd s_wrcmd
always@(*)begin
    CM0_grped=OFF;
    CM1_grped=OFF;
    TagCM_grped=OFF;
    //better safe thaan sorrry make data_counterr=0; for every where it needs
    done=0;
    s_wrcmd=0;
    s_wdata=0;
    r_rcmd=0;
    sampleTags=0;
    sampledatas=0;
    Fetchsample=0;
    validupdate=0;
    dirtyupdate=0;
    RDATA=0;
    Fetched_datar=0;
    tag_to_TCM=tag;
    wdata_to_CM0=0;
    wdata_to_CM1=0;
    ACK=0;
    case(State)
    NOREQ:begin
        if(req_CPU)
        begin
            if(data_counter==0)begin
                Stater=NOREQ;
                data_counterr=1;
                TagCM_grped=TOREAD;
            end
            else begin//data_counter
                Stater=CHECK;
                data_counterr=0;               
                TagCM_grped=OFF;
                sampleTags=1;
            end

            //read tag below 
                CM0_grped=OFF;
                CM1_grped=OFF;

        end
        else begin
            Stater=NOREQ;
            data_counterr=0;
        end
    end
    CHECK:begin
        if((sampleTag==tag)&&(valid[index]))begin
            //hit
            //u haave to read anyway to make chacnge 
            TagCM_grped=OFF;
            if(data_counter==1)begin
                Stater=write?WRITE:READ;
                CM0_grped=OFF;
                CM1_grped=OFF;
                sampledatas=1;
                data_counterr=0;
            end
            else begin
                Stater=CHECK;
                data_counterr=1;
                if(index[6])begin
                    CM0_grped=OFF;
                    CM1_grped=TOREAD;
                end
                else begin
                    CM0_grped=TOREAD;
                    CM1_grped=OFF;
                end

            end
        end
        else begin//miss
            if(valid[index]==0 || dirty[index]==0)begin//invalid data or (tag doesnt mathc and not dirty) do FETCH
                Stater=FETCH_CMD;
                data_counterr=3;
            end   
            else begin//tag not match and dirty is 1 case
                //data was dirty
                TagCM_grped=OFF;
                if(data_counter==1)begin
                    Stater=STORE_DATA;
                    data_counterr=3;//needs to be 3
                    CM0_grped=OFF;
                    CM1_grped=OFF;
                    sampledatas=1;
                end
                else begin
                    Stater=CHECK;
                    data_counterr=1;
                    if(CM_select)begin//CM1 slececct
                        CM0_grped=OFF;
                        CM1_grped=TOREAD;
                    end
                    else begin
                        CM0_grped=TOREAD;
                        CM1_grped=OFF;
                    end
                end
            end    
        end
    end
    READ:begin
        //this is a done stage onely as only entry is via CHECK HTIT
        done=1;//for read done is 1 and for 
        case(offset)
            0:RDATA=sampledata[31:0];
            1:RDATA=sampledata[63:32];
            2:RDATA=sampledata[95:64];
            3:RDATA=sampledata[127:96];
            default:RDATA=sampledata[31:0];
        endcase
        Stater=req_CPU?READ:NOREQ;
        data_counterr=0;
    end

    WRITE:begin
        if(data_counter==0)begin
            Stater=WRITE;
            data_counterr=1;
            dirtyupdate=1;
        if(CM_select)begin//CM1 has it
            CM0_grped=OFF;
            TagCM_grped=OFF;
            CM1_grped=TOWRITE;
            wdata_to_CM1=(sampledata&(~(128'HFFFFFFFF<<(offset<<5)))) | 128'(WDATA)<<(offset<<5);
        end 
        else begin//CM0 has it
            CM0_grped=TOWRITE;
            TagCM_grped=OFF;
            CM1_grped=OFF;
            wdata_to_CM0=(sampledata&(~(128'HFFFFFFFF<<(offset<<5)))) | 128'(WDATA)<<(offset<<5);
        end
        end
        else begin
            Stater=req_CPU?WRITE:NOREQ;//only if it goes 0 assert
            done=1;
            data_counterr=req_CPU?2'b01:2'b0;
            //datacounter=0 will not be done cos 4 state handshake waits for req to go zero and bc of default condition at noreq it will go to zero
        end
    //2 types of entry one is vai cjeck and fetchread


    end

    STORE_DATA:begin//evictor routine
        //sampledata has data to store 
        //send data in 3 2 1 0
        //rerquies entry  data_counter as 3
        if(data_counter==0)
        begin
            Stater=s_fifo_full?STORE_DATA:STORE_ACK;
            data_counterr=0;
        end
        else begin
            Stater=STORE_DATA;
//            s_wdata={2'b01,sampleTag,index,data_counter,32'(sampledata[(data_counter<<5):+32])};
            data_counterr=s_fifo_full?data_counter:data_counter-1;

        end
            s_wrcmd = ~s_fifo_full;
            case(data_counter)
                0:s_wdata={2'b01,sampleTag,index,data_counter,32'(sampledata[31:0])};
                1:s_wdata={2'b01,sampleTag,index,data_counter,32'(sampledata[63:32])};
                2:s_wdata={2'b01,sampleTag,index,data_counter,32'(sampledata[95:64])};
                3:s_wdata={2'b01,sampleTag,index,data_counter,32'(sampledata[127:96])};
                default:s_wdata={2'b01,sampleTag,index,data_counter,32'(sampledata[31:0])};
            endcase
    end
        STORE_ACK:begin
            data_counterr=0;//FETCH_CMD has use for it 
            if(r_empty)begin//no response 
                Stater=STORE_ACK;
            end
            else begin//there is but vlid?
                r_rcmd=1;//have to pop anyway
                ACK=(r_rdata==({2'b10,34'b0,sampleTag,index}));
                Stater=ACK?FETCH_CMD:STORE_ACK;
            end
        end
        FETCH_CMD:begin
                data_counterr=3;//  0 is not neccesaryly dangerous in FETCH_READ but 3 is what been expected 
                if(s_fifo_full)begin//cant do fetch; 
                    Stater=CHECK;
                    s_wrcmd=0;
                end
                else begin//does fetch
                    Stater=FETCH_READ;//leaving out FETCH_POLL intensionally to chekc can it be logically done without it
                    s_wrcmd=1;
                    s_wdata={1'b1,35'b0,req_addr[13:2]};//askign for new data
                end
        end
        FETCH_READ:begin//will follow ditch it until i get it
            if(r_empty)begin
                Stater=FETCH_READ;
                data_counterr=3;
            end
            else begin
                r_rcmd=1;//have to pop anyway
                data_counterr=r_rdata[33:32];//offset
                ACK=(r_rdata[47:34]==({2'b10,req_addr[13:2]}));//reusing cos it has the same functionality and temporal mutual exclusivity
                if(ACK)begin
                    Stater=(data_counterr==0)?FETCH_WRITE:FETCH_READ;//FETCH_WRITE has use for it needs entry as 0 to do write  
                    Fetchsample=1;
                end
                else begin
                    Stater=FETCH_READ;
                    Fetchsample=0;
                end
                Fetched_datar =(Fetched_data & ~(128'h0000_0000_FFFF_FFFF << (data_counterr << 5))) |({96'b0, r_rdata[31:0]} << (data_counterr << 5));

            end

        end
        FETCH_WRITE:begin
            //data_counter will enter with 0 
            //why shoudlnt i write here lets try - works now
            //if write then write with the updated value and update dirty=1
            //if read just make sampled data be the Fetched_data but dont give done until write is finished and dirty is 0
            //Tag change is same for both 

            if(0==data_counter)begin
                Stater=FETCH_WRITE;
                data_counterr=1;
                TagCM_grped=TOWRITE;
            if(write)begin//select CM based on CM-slect and modify and do change
                CM0_grped=CM_select?OFF:TOWRITE;
                CM1_grped=CM_select?TOWRITE:OFF;
                dirtyupdate=1;
                validupdate=1;
                wdata_to_CM1=Fetched_data&(~(128'HFFFFFFFF<<(offset<<5))) | 128'(WDATA)<<(offset<<5);//replace alrasy existing one with write needed
                wdata_to_CM0=Fetched_data&(~(128'HFFFFFFFF<<(offset<<5))) | 128'(WDATA)<<(offset<<5);//replace alrasy existing one with write needed
            end
            else begin
                CM0_grped=CM_select?OFF:TOWRITE;
                CM1_grped=CM_select?TOWRITE:OFF;
                wdata_to_CM1=Fetched_data;
                wdata_to_CM0=Fetched_data;
                dirtyupdate=1;
                validupdate=1;
            end
            end
            else if(data_counter==1 && req_CPU==1)//when there is still req given
            begin
                data_counterr=1;
                Stater=FETCH_WRITE; 
                data_counterr=1;
                done=1;
                if(~write)begin//read
                case(offset)
                    0:RDATA=Fetched_data[31:0];
                    1:RDATA=Fetched_data[63:32];
                    2:RDATA=Fetched_data[95:64];
                    3:RDATA=Fetched_data[127:96];
                    default:RDATA=Fetched_data[31:0];
                endcase
                end
                else 
                RDATA=0;//write
                //write?0:Fetched_data;//if it was a read --> have to give a case statements here 
            end
            else begin
                Stater=NOREQ;
                done=0;
                data_counterr=0;
            end
        end
    default:begin
        Stater=NOREQ;
        done=0;
        data_counterr=0;
        CM0_grped=OFF;
        CM1_grped=OFF;
        RDATA=0;
        wdata_to_CM1=0;
        wdata_to_CM0=0;
        dirtyupdate=0;
        validupdate=0;
        TagCM_grped=OFF;
        Fetchsample=0;
        sampledatas=0;
        sampleTags=0;
    end
    endcase
end
//clk here is core_clk in core 
//3 MEMORIES DONE
SRAM1RW128x8 TagSram(.A(addr_to_TCM),.CE(clk),.WEB(WEB_TagCM),.OEB(OEB_TagCM),.CSB(CSB_TagCM),.I({3'b0,tag_to_TCM}),.O(Tagoutput));//Tag sram 
SRAM1RW64x128 CM0(.A(addr_to_CM),.CE(clk),.WEB(WEB_CM0),.OEB(OEB_CM0),.CSB(CSB_CM0),.I(wdata_to_CM0),.O(rdata_from_CM0));
SRAM1RW64x128 CM1(.A(addr_to_CM),.CE(clk),.WEB(WEB_CM1),.OEB(OEB_CM1),.CSB(CSB_CM1),.I(wdata_to_CM1),.O(rdata_from_CM1));


endmodule