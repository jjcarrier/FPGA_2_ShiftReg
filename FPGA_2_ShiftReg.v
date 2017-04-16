`timescale 1ns / 1ps
////////////////////////////////////////////////////////////////////////////////
// Author:        Jon Carrier
//
// Create Date:   21:33:11 01/26/2012
// Module Name:   FPGA_2_ShiftReg
// Description:   Simple implementation of a shift register driver for 74HC595
//
// Dependencies:  CLK=24MHz. Slower clocks should also work. If a faster CLK is
//                used, the parameters below may need adjusting
//
////////////////////////////////////////////////////////////////////////////////

module FPGA_2_ShiftReg(CLK, BYTE_IN, EN_IN, RDY, RCLK, SRCLK, OE, SER_OUT);

//----------------------------CONTROL SIGNALS-----------------------------------
input CLK;
input [7:0] BYTE_IN;  //8-bit input data
input EN_IN;  //BYTE_IN ENABLE, indicates the input data is valid
output RDY;   //A ready flag indicator, brought low when EN_IN=1 and stays low
              //until EN_IN=0 and the data has been shifted out on SER_OUT


//-----------------------PHYSICAL PIN CONNECTIONS-------------------------------
output RCLK;    //Register CLK, pushes the FIFO data to the driver outputs
output SRCLK;   //Positive Edge Triggered Shift Register CLK
output OE;      //Output Enable (Active Low)
output SER_OUT; //The serial data output
//------------------------------------------------------------------------------

//NOTE: Tie SRCLR to VCC since we never need to clear
reg [8:0] shift = 0;
reg RCLK        = 0;
reg SRCLK       = 0;
reg RDY         = 1;
wire OE;

//==============================================================================
//--------------------------------PARAMETERS------------------------------------
//==============================================================================
//If we assume CLK=24MHz, then T~=42nS
//If VCC=3.3V, SRCLK at worst case is capable of 5MHz and at best 25MHz
//Lets assume SRCLK=12MHz, T_SCLK~=84nS
//See page 7 of the SN74HC595 datasheet for the parameters below

//------------------------------NUMBER OF BITS----------------------------------
parameter N = 2; //This parameter is used on several registers/parameters below

//---------------------PULSE DURATION PARAMETER (PAGE7)-------------------------
//This parameter is used to specify in how many clock cycles of CLK must
//occur prior to setting or unsetting SRCLK/RCLK HI or LO
parameter [N-1:0] pulse_duration = 3; //safety time > 100ns, >=3 CLK cycles

//---------------------SETUP TIME PARAMETER (PAGE7)-----------------------------
//This parameter is used to control how much time is required to setup the
//SER_OUT signal prior to setting SRCLK HI.
//Note there is no required hold duration, once the signal is written to SER,
//and SRCLK has gone HI, the next signal can be immediately setup
parameter [N-1:0] setup_time = 3; //Safety time > 125ns, >=3 CLK cycles

//==============================================================================
//----------------------------ASSIGN THE SER_OUT--------------------------------
//==============================================================================
//The SER_OUT port can be thought of as a wire to the MSB of an 8-bit shift reg
wire SER_OUT;
assign SER_OUT = shift[8]; //shift data out using MSBF

//==============================================================================
//--------------------------CREATE THE SRCLK SIGNAL-----------------------------
//==============================================================================
//Create the SRCLK signal that will be used to clock-in the serial data
reg [N-1:0] clk_cnt   = 0;
reg [1:0] SRCLK_state = 0;
reg SRCLK_toggle      = 0; //Instructs the process to toggle SRCLK for a period of time

always @ ( posedge CLK ) begin
  case ( SRCLK_state )
    0: begin //Wait for SRCLK_toggle=1
      if ( SRCLK_toggle == 1 ) begin
        SRCLK_state <= SRCLK_state + 1;
        SRCLK       <= 0; //Make sure SRCLK is low
        clk_cnt     <= 0;
      end
    end
    1: begin //Wait for the defined setup time, prior to setting SRCLK HI
      if ( clk_cnt == ( setup_time - 1 ) ) begin
        SRCLK       <= 1;
        clk_cnt     <= 0;
        SRCLK_state <= SRCLK_state + 1;
      end else begin
        clk_cnt <= clk_cnt + 1;
      end
    end
    2: begin //Wait for the defined pulse duration, prior to setting SRCLK LO
      if ( clk_cnt == ( pulse_duration - 1 ) ) begin
        SRCLK       <= 0;
        clk_cnt     <= 0;
        SRCLK_state <= SRCLK_state + 1;
      end else begin
        clk_cnt <= clk_cnt + 1;
      end
    end
    3: begin //Wait for SRCLK_toggle=0
      if ( SRCLK_toggle == 0 ) SRCLK_state <= 0;
    end
  endcase
end

//==============================================================================
//--------------------------CREATE THE RCLK SIGNAL------------------------------
//==============================================================================
//Create the RCLK signal that will be used to clock-out the parallel data
reg [N-1:0] clk_cnt2 = 0;
reg [1:0] RCLK_state = 0;
reg RCLK_toggle = 0; //Instructs the process to toggle RCLK for a period of time

always @ ( posedge CLK ) begin
  case ( RCLK_state )
    0: begin //Wait for RCLK_toggle=1
      if ( RCLK_toggle == 1 ) begin
        RCLK_state  <= RCLK_state + 1;
        RCLK        <= 0; //Make sure RCLK is low
        clk_cnt2    <= 0;
      end
    end
    1: begin //Wait for the defined setup time, prior to setting RCLK HI
      if ( clk_cnt2 == ( setup_time - 1 ) ) begin
        RCLK        <= 1;
        clk_cnt2    <= 0;
        RCLK_state  <= RCLK_state + 1;
      end else begin
        clk_cnt2 <= clk_cnt2 + 1;
      end
    end
    2: begin //Wait for the defined pulse duration, prior to setting SRCLK LO
      if ( clk_cnt2 == ( pulse_duration - 1 ) ) begin
        RCLK        <= 0;
        clk_cnt2    <= 0;
        RCLK_state  <= RCLK_state + 1;
      end else begin
        clk_cnt2 <= clk_cnt2 + 1;
      end
    end
    3: begin //Wait for RCLK_toggle=0
      if ( RCLK_toggle == 0 ) RCLK_state <= 0;
    end
  endcase
end

//==============================================================================
//-------------------CREATE THE FUNCTIONAL SWITCHING LOGIC----------------------
//==============================================================================
reg [1:0] state = 0; //Statemachine variable
reg [1:0] substate = 0;
reg [2:0] cnt = 0;
reg init_done = 0;
always @ ( posedge CLK ) begin
  case ( state )
    0: begin //-----------------------------Populate the FPGA's shift register
      if ( EN_IN == 1 ) begin //Only start the statemachine when input is enabled
        shift[7:0]   <= BYTE_IN;
        //shift[8]   <= 0;
        cnt          <= 0;
        state        <= state + 1;
        RDY          <= 0;
        SRCLK_toggle <= 0;
        RCLK_toggle  <= 0;
        substate     <= 0;
      end else begin
        RDY          <= 1;
        cnt          <= 0;
        SRCLK_toggle <= 0;
        RCLK_toggle  <= 0;
        state        <= 0;
        substate     <= 0;
      end
    end
    1: begin //-----------------------------------------Push the bits out MSBF
      case ( substate )
        0: begin //PUSH DATA ON SER
          shift[8:1]  <= shift[7:0];
          shift[0]    <= 0;
          substate    <= substate + 1;
        end
        1: begin //PULSE SRCLK
          SRCLK_toggle  <= 1;
          substate      <= substate + 1;
        end
        2: begin //TURN OFF THE TOGGLE BIT
          if ( SRCLK == 1 ) begin
            SRCLK_toggle  <= 0;
            substate      <= substate + 1;
          end
        end
        3: begin //WHEN SRCLK GOES LOW, CHECK & UPDATE cnt
          if ( SRCLK == 0 ) begin
            if ( cnt == 7 ) begin
              //All bits have been shifted
              state <= state + 1;
              cnt   <= 0;
            end else begin
              //We have more bits to shift
              cnt <= cnt + 1;
            end
            substate <= 0;
          end
        end
      endcase
    end
    2: begin //--------------------------Update & Activate the parallel output
      //First Pulse RCLK
      //Then indicate init_done
      case ( substate )
        0: begin //PULSE RCLK
          RCLK_toggle <= 1;
          substate    <= substate + 1;
        end
        1: begin //TURN OFF THE TOGGLE BIT
          if ( RCLK == 1 ) begin
            RCLK_toggle <= 0;
            substate    <= substate + 1;
          end
        end
        2: begin //WHEN RCLK GOES LOW, CHECK & UPDATE cnt
          if ( RCLK == 0 ) begin
            state     <= 0;
            substate  <= 0;
            init_done <= 1;
            RDY       <= 1;
          end
        end
      endcase
    end
    default: begin
      state     <= 0;
      substate  <= 0;
      init_done <= 0;
      RDY       <= 1;
    end
  endcase
end

//==============================================================================
//------------------------INITIALIZATION DONE PROCESS---------------------------
//==============================================================================
//This is when the shift register's outputs are switched from HI-Z to LO-Z.
//We will use this as the point in time when we should activate the outputs
//after powerup. At powerup the chip will be in HI-Z state since the data will
//not be valid. Once the user feeds data into this module, and the module
//processes the request, the shift register's output will be enabled
//permenantly. The subsequent data that is fed into this module will be updated
//once all 8-bits are shifted into position. This is done in the logic process
//above.
reg EN_OUT = 0;
always @ ( posedge CLK ) begin
  if ( init_done == 1 ) begin
    EN_OUT <= 1;
  end else begin
    EN_OUT <= 0;
  end
end

assign OE = ~EN_OUT; //Invert OE since it is active low

endmodule