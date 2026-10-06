lappend search_path \
    /fetools/work_area/frontend/SAED32_EDK/lib/stdcell_rvt/db_nldm \
    /fetools/work_area/frontend/SAED32_EDK/lib/sram/db_nldm
set target_library [list saed32rvt_ss0p95v25c.db]
#shouldnt append it cos it has placeholder yourlibrary.db
set synthetic_library [list dw_foundation.sldb]
set link_library "* $target_library saed32sram_ss0p95v25c.db $synthetic_library"
#shouldnt append it cos it has placeholder * and yourlibrary.db
set designer "Tamil Selvan Elangovan"
set symbol_library
#not a problem in shell only in design vision it will create a problem if unassined

read_sverilog -rtl {Cache.sv}
link
check_design
write_file -format verilog -hier -out Cache_unmapped.v
compile_ultra
write_file -format verilog -hier -out Cache_mapped.v
write_file -format ddc -hier -out Cache_mapped.ddc