# Addition-of-2-vectors-from-DRAM
A unit that fetches two vectors of signed 8-bit data from a DRAM memory,  adds them together and writes the resulting vector back to a different location in the DRAM.  

Designed the DUT that builds a near-memory vector adder which computes 𝐴⃑=𝐵⃑⃑ + 𝐶⃑ by reading two SDRAM memory blocks (starting at address src0 for 𝐵⃑⃑ and src1 for 𝐶⃑) and writing one 
block starting at address dst for 𝐴⃑. A command is the tuple {dst, src0, src1} and is issued with a valid signal.  The DUT asserts a ready signal when it is ready to receive a command.  The DUT 
latches a command on any cycle where (vaild && ready) is true. Upon every acceptance, ready must be set to low on the next cycle and hold low until it is ready to accept a new command. 
When valid is low and the DUT asserts ready the test is complete. This is the done state, and the test fixture will evaluate the contents of the DRAM. 
