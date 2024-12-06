vlib work
vmap work ./work

# Compile design
vlog i2c_slave.sv  
vlog i3c_primary_master.sv      
vlog I3C_secondary master and slave_module.sv     
vlog I3C_slave1.sv   
vlog i3c_system.sv
vlog tb_i3c_system_updated.sv 

# Load the design into the simulator
vsim -voptargs=+acc work.tb_i3c_system_updated

# Run the simulation to completion
run -all