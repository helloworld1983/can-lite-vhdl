--////////////////////////////////////////////////////////////////////
--//                                                              ////
--//  Adapted from:                                               ////
--//  https://opencores.org/project,a_vhdl_can_controller         ////
--//                                                              ////
--//  Which is a consolidated translation of:                     ////
--//  http://www.opencores.org/project,can                        ////
--//  By:  Igor Mohor                                             ////
--//       igorm@opencores.org                                    ////
--//                                                              ////
--//  Which is a non-attributed clone of:                         ////
--//  HDL implementation of a controller area network             ////
--//  By: Anthony Richard Marino, Rowan University                ////
--//                                                              ////
--////////////////////////////////////////////////////////////////////
--//                                                              ////
--// Copyright (C) 2002, 2003, 2004 Authors                       ////
--//                                                              ////
--// This source file may be used and distributed without         ////
--// restriction provided that this copyright statement is not    ////
--// removed from the file and that any derivative work contains  ////
--// the original copyright notice and the associated disclaimer. ////
--//                                                              ////
--// This source file is free software; you can redistribute it   ////
--// and/or modify it under the terms of the GNU Lesser General   ////
--// Public License as published by the Free Software Foundation; ////
--// either version 2.1 of the License, or (at your option) any   ////
--// later version.                                               ////
--//                                                              ////
--// This source is distributed in the hope that it will be       ////
--// useful, but WITHOUT ANY WARRANTY; without even the implied   ////
--// warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR      ////
--// PURPOSE.  See the GNU Lesser General Public License for more ////
--// details.                                                     ////
--//                                                              ////
--// You should have received a copy of the GNU Lesser General    ////
--// Public License along with this source; if not, download it   ////
--// from http://www.opencores.org/lgpl.shtml                     ////
--//                                                              ////
--// The CAN protocol is developed by Robert Bosch GmbH and       ////
--// protected by patents. Anybody who wants to implement this    ////
--// CAN IP core on silicon has to obtain a CAN protocol license  ////
--// from Bosch.                                                  ////
--//                                                              ////
--////////////////////////////////////////////////////////////////////

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.CanBus;

entity CanLite is
    generic ( --! Default configuration register values
        FIFO_DEPTH                  : positive;
        BAUD_RATE_PRESCALAR         : positive range 1 to 64 := 1;
        SYNCHRONIZATION_JUMP_WIDTH  : positive range 1 to 4 := 3;
        TIME_SEGMENT_1              : positive range 1 to 16 := 8;
        TIME_SEGMENT_2              : positive range 1 to 8 := 3;
        TRIPLE_SAMPLING             : boolean := true
    );
    port (
        AppClock    : in  std_logic; --! Application clock
        Reset_n     : in  std_logic; --! Active-low reset
        
        RxFrame     : out CanBus.Frame; --! CAN frame read from RX FIFO buffer
        RxStrobe    : in  std_logic; --! High pulse for reading RxFrame from FIFO buffer
        RxFifoEmpty : out std_logic; --! Empty flag of RX FIFO buffer
                
        TxFrame     : in  CanBus.Frame; --! CAN frame to be loaded into TX FIFO buffer
        TxStrobe    : in  std_logic; --! High pulse for loading TxFrame into FIFO buffer
        TxFifoFull  : out std_logic; --! High if TxFifo is full
        TxAck       : out std_logic; --! High pulse when a message was successfully transmitted
        
        Status      : out CanBus.Status; --! See CanBus_pkg.vhdl
        
        CanClock    : in  std_logic; --! Base clock for CAN timing (24MHz recommended)
        CanRx       : in  std_logic; --! RX input from CAN transceiver
        CanTx       : out std_logic --! TX output to CAN transceiver
    );
end entity CanLite;

architecture Behavioral of CanLite is
    component CanFifo is
        generic (
            DEPTH   : positive
            );
        port (
            Clock       : in  std_logic;
            Reset_n     : in  std_logic;
            FrameIn     : in  CanBus.Frame;
            WriteEnable : in  std_logic;
            ReadEnable  : in  std_logic;
            FrameOut    : out CanBus.Frame;
            Full        : out std_logic;
            Empty       : out std_logic
        );
    end component CanFifo;

    component CanLiteBitStreamProcessor is
        port (
            clk                     : in  std_logic;
            rst                     : in  std_logic;
            reset_mode              : in  std_logic;
            tx_request              : in  std_logic;
            TxFrame                 : in  CanBus.Frame;
            
            -- Outputs from CanLiteBitTimingLogic
            sample_point            : in  std_logic;
            sampled_bit             : in  std_logic;
            sampled_bit_q           : in  std_logic;
            tx_point                : in  std_logic;
            hard_sync               : in  std_logic;
            
            RxFrame                 : out CanBus.Frame;
            tx_state                : out std_logic;
            tx_state_q              : out std_logic;
            rx_idle                 : out std_logic;
            transmitting            : out std_logic;
            transmitter             : out std_logic;
            go_rx_inter             : out std_logic;
            not_first_bit_of_inter  : out std_logic;
            rx_inter                : out std_logic;
            set_reset_mode          : out std_logic;
            node_bus_off            : out std_logic;
            error_status            : out std_logic;
            rx_err_cnt              : out unsigned(7 downto 0);
            tx_err_cnt              : out unsigned(7 downto 0);
            transmit_status         : out std_logic;
            receive_status          : out std_logic;
            tx_successful           : out std_logic;
            need_to_tx              : out std_logic;
            node_error_passive      : out std_logic;
            tx                      : out std_logic;
            tx_next                 : out std_logic;
            go_overload_frame       : out std_logic;
            go_error_frame          : out std_logic;
            go_tx                   : out std_logic;
            send_ack                : out std_logic
        );
    end component CanLiteBitStreamProcessor;

    component CanLiteBitTimingLogic
        generic ( --! Default configuration register values
            BAUD_RATE_PRESCALAR        : positive range 1 to 64 := 1;
            SYNCHRONIZATION_JUMP_WIDTH : positive range 1 to 4 := 3;
            TIME_SEGMENT_1             : positive range 1 to 16 := 8;
            TIME_SEGMENT_2             : positive range 1 to 8 := 3;
            TRIPLE_SAMPLING            : boolean := true
        );
        port (
            clk                     : in  std_logic;
            rst                     : in  std_logic;
            rx                      : in  std_logic;
            tx                      : in  std_logic;
            sample_point            : out std_logic;
            sampled_bit             : out std_logic;
            sampled_bit_q           : out std_logic;
            tx_point                : out std_logic;
            hard_sync               : out std_logic;
            rx_idle                 : in  std_logic;
            rx_inter                : in  std_logic;
            transmitting            : in  std_logic;
            transmitter             : in  std_logic;
            go_rx_inter             : in  std_logic;
            tx_next                 : in  std_logic;
            go_overload_frame       : in  std_logic;
            go_error_frame          : in  std_logic;
            go_tx                   : in  std_logic;
            send_ack                : in  std_logic;
            node_error_passive      : in  std_logic
        );
    end component CanLiteBitTimingLogic;

    signal rst                      :  std_logic; --! Not Reset_n (asynchronous)
    signal reset_mode               :  std_logic; --! Synchronous reset pulse
    signal CanRx_q, CanRx_q_q, CanTx_q  :  std_logic; --! Registered CAN signals
    signal RxFrame_q, TxFrame_q     :  CanBus.Frame; --! FIFO input/output data
    signal TxRequest                :  std_logic; --! New message ready for bit stream processor
    signal TxFifoEmpty, RxFifoFull  :  std_logic; --! FIFO flags
    signal TxFifoReadEnable, RxFifoWriteEnable  :  std_logic; --! FIFO control
  
   -- Output signals from CanLiteBitTimingLogic module 
    signal sample_point             :  std_logic;   
    signal sampled_bit              :  std_logic;   
    signal sampled_bit_q            :  std_logic;   
    signal tx_point                 :  std_logic;   
    signal hard_sync                :  std_logic;
    
   -- Outputs from CanLiteBitStreamProcessor 
    signal tx_state                 :  std_logic;   
    signal tx_state_q               :  std_logic;              
    signal rx_idle                  :  std_logic;   
    signal transmitting             :  std_logic;   
    signal transmitter              :  std_logic;   
    signal go_rx_inter              :  std_logic;   
    signal not_first_bit_of_inter   :  std_logic;   
    signal rx_inter                 :  std_logic;   
    signal set_reset_mode           :  std_logic;   
    signal node_bus_off             :  std_logic;   
    signal error_status             :  std_logic;   
    signal rx_err_cnt               :  unsigned(7 downto 0);   
    signal tx_err_cnt               :  unsigned(7 downto 0);   
    signal rx_err_cnt_dummy         :  std_logic;   --  The MSB is not displayed. It is just used for easier calculation (no counter overflow).
    signal tx_err_cnt_dummy         :  std_logic;   --  The MSB is not displayed. It is just used for easier calculation (no counter overflow).
    signal transmit_status          :  std_logic;   
    signal receive_status           :  std_logic;   
    signal tx_successful            :  std_logic;   
    signal need_to_tx               :  std_logic;      
    signal node_error_passive       :  std_logic;       
    signal tx_next                  :  std_logic;   
    signal go_overload_frame        :  std_logic;   
    signal go_error_frame           :  std_logic;   
    signal go_tx                    :  std_logic;   
    signal send_ack                 :  std_logic;
    
begin
    rst <= not Reset_n;
    RxFifoWriteEnable <= go_rx_inter and not tx_state;
    TxAck <= tx_successful;
    CanTx <= CanTx_q;
    Status.State <=
        CanBus.STATE_RESET when Reset_n = '0' else
        CanBus.STATE_BUS_OFF when node_bus_off = '1' else
        CanBus.STATE_ERROR_PASSIVE when node_error_passive = '1' else
        CanBus.STATE_ERROR_ACTIVE;
    Status.ErrorWarning <= error_status;

    --! Reset pulse required for bit stream processor
    process (AppClock, Reset_n)
    begin
        if Reset_n = '0' then
            reset_mode <= '1';
        elsif rising_edge(AppClock) then
            if set_reset_mode = '1' then
                reset_mode <= '1';
            elsif reset_mode = '1' then
                reset_mode <= '0';
            end if;
        end if;
    end process;
    
    --! Double-buffer CAN RX signal
    process (AppClock, Reset_n)
    begin
        if (Reset_n = '0') then
            CanRx_q <= '1';
            CanRx_q_q <= '1';
        elsif (rising_edge(AppClock)) then
            CanRx_q <= CanRx;
            CanRx_q_q <= CanRx_q;
        end if;
    end process;

    --! Tx FIFO control
    process (AppClock, Reset_n)
    begin
        if Reset_n = '0' then
            TxFifoReadEnable <= '0';
            TxRequest <= '0';
        elsif rising_edge(AppClock) then
            if (
                TxRequest = '1' or --! Active request
                need_to_tx = '1' or --! Processing request 
                TxFifoReadEnable = '1' --! Single pulse
            ) then
                TxFifoReadEnable <= '0';
            elsif TxFifoEmpty = '0' then --! New request
                TxFifoReadEnable <= '1';
            end if;
            if TxFifoReadEnable = '1' then --! Delay by one clock cycle
                TxRequest <= '1';
            elsif need_to_tx = '1' then --! Request acknowledged
                TxRequest <= '0';
            end if;
        end if;
    end process;
    
    process (AppClock, Reset_n)
    begin
        if Reset_n = '0' then
            Status.Overflow <= '0';
        elsif rising_edge(AppClock) then
            if RxFifoWriteEnable = '1' and RxFifoFull = '1' then
                Status.Overflow <= '1';
            elsif RxFifoFull = '0' then
                Status.Overflow <= '0';
            end if;
        end if;
    end process;
       
    TxFifo : CanFifo
        generic map (
            DEPTH => 2
        )
        port map (
            Clock => AppClock,
            Reset_n => Reset_n,
            FrameIn => TxFrame,
            WriteEnable => TxStrobe,
            ReadEnable => TxFifoReadEnable,
            FrameOut => TxFrame_q,
            Full => TxFifoFull,
            Empty => TxFifoEmpty
        );
        
    RxFifo : CanFifo
        generic map (
            DEPTH => 2
        )
        port map (
            Clock => AppClock,
            Reset_n => Reset_n,
            FrameIn => RxFrame_q,
            WriteEnable => RxFifoWriteEnable,
            ReadEnable => RxStrobe,
            FrameOut => RxFrame,
            Full => RxFifoFull,
            Empty => RxFifoEmpty
        );
        
    BitTimingLogic : CanLiteBitTimingLogic
        generic map (
            BAUD_RATE_PRESCALAR => BAUD_RATE_PRESCALAR,
            SYNCHRONIZATION_JUMP_WIDTH => SYNCHRONIZATION_JUMP_WIDTH,
            TIME_SEGMENT_1 => TIME_SEGMENT_1,
            TIME_SEGMENT_2 => TIME_SEGMENT_2,
            TRIPLE_SAMPLING => TRIPLE_SAMPLING
        )
        port map (
            clk => AppClock,
            rst => rst,
            rx => CanRx_q_q,
            tx => CanTx_q,
            sample_point => sample_point,
            sampled_bit => sampled_bit,
            sampled_bit_q => sampled_bit_q,
            tx_point => tx_point,
            hard_sync => hard_sync,
            rx_idle => rx_idle,
            rx_inter => rx_inter,
            transmitting => transmitting,
            transmitter => transmitter,
            go_rx_inter => go_rx_inter,
            tx_next => tx_next,
            go_overload_frame => go_overload_frame,
            go_error_frame => go_error_frame,
            go_tx => go_tx,
            send_ack => send_ack,
            node_error_passive => node_error_passive
        );   
   
   
    BitStreamProcessor : CanLiteBitStreamProcessor
        port map (
            clk => AppClock,
            rst => rst,
            sample_point => sample_point,
            sampled_bit => sampled_bit,
            sampled_bit_q => sampled_bit_q,
            tx_point => tx_point,
            hard_sync => hard_sync,
            reset_mode => reset_mode,
            tx_request => TxRequest,
            tx_state => tx_state,
            tx_state_q => tx_state_q,
            rx_idle => rx_idle,
            transmitting => transmitting,
            transmitter => transmitter,
            go_rx_inter => go_rx_inter,
            not_first_bit_of_inter => not_first_bit_of_inter,
            rx_inter => rx_inter,
            set_reset_mode => set_reset_mode,
            node_bus_off => node_bus_off,
            error_status => error_status,
            rx_err_cnt => rx_err_cnt,
            tx_err_cnt => tx_err_cnt,
            transmit_status => transmit_status,
            receive_status => receive_status,
            tx_successful => tx_successful,
            need_to_tx => need_to_tx,
            node_error_passive => node_error_passive,
            TxFrame => TxFrame_q,
            RxFrame => RxFrame_q,
            tx => CanTx_q,
            tx_next => tx_next,
            go_overload_frame => go_overload_frame,
            go_error_frame => go_error_frame,
            go_tx => go_tx,
            send_ack => send_ack
        ); 
end architecture Behavioral;


library ieee;
use ieee.std_logic_1164.all;
use work.CanBus;

entity CanFifo is
    generic (
        DEPTH   : positive := 8
    );
    port (
        Clock       : in  std_logic;
        Reset_n     : in  std_logic;
        FrameIn     : in  CanBus.Frame;
        WriteEnable : in  std_logic;
        ReadEnable  : in  std_logic;
        FrameOut    : out CanBus.Frame;
        Full        : out std_logic;
        Empty       : out std_logic
    );
end entity CanFifo;

-- This architecture requires a one clock cycle data hold time before WriteEnable is asserted
architecture Behavioral of CanFifo is
    type MemoryType is array (0 to DEPTH - 1) of CanBus.Frame;
    signal Memory     : MemoryType;
    signal Counter    : natural range 0 to DEPTH;
    signal ReadIndex, WriteIndex   : natural range 0 to DEPTH - 1;
    signal Full_d, Empty_d  : std_logic;
begin
    FrameOut <= Memory(ReadIndex);
    Full <= Full_d;
    Empty <= Empty_d;
    Full_d <= '1' when Counter = DEPTH else '0';
    Empty_d <= '1' when Counter = 0 else '0';

    process (Clock, Reset_n)
    begin
        if Reset_n = '0' then
            Counter <= 0;
            ReadIndex <= DEPTH - 1;
            WriteIndex <= 0;
            Memory <= (others => (Id => (others => '0'), Rtr => '0', Dlc => (others => '0'), Data => (others => (others => '0')))); 
        elsif rising_edge(Clock) then
            if WriteEnable = '1' and Full_d = '0' and ReadEnable = '0' then
                Counter <= Counter + 1;
            elsif WriteEnable = '0' and ReadEnable = '1' and Empty_d = '0' then
                Counter <= Counter - 1;
            end if;
            if WriteEnable = '1' and Full_d = '0' then
                Memory(WriteIndex) <= FrameIn;
                if WriteIndex = DEPTH - 1 then
                    WriteIndex <= 0;
                else
                    WriteIndex <= WriteIndex + 1;
                end if;
            end if;
            if ReadEnable = '1' and Empty_d = '0' then
                if ReadIndex = DEPTH - 1 then
                    ReadIndex <= 0;
                else
                    ReadIndex <= ReadIndex + 1;
                end if;
            end if;
        end if;
    end process;
end architecture Behavioral;


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity CanLiteBitTimingLogic is
    generic (
        BAUD_RATE_PRESCALAR        : positive range 1 to 64 := 1;
        SYNCHRONIZATION_JUMP_WIDTH : positive range 1 to 4 := 3;
        TIME_SEGMENT_1             : positive range 1 to 16 := 8;
        TIME_SEGMENT_2             : positive range 1 to 8 := 3;
        TRIPLE_SAMPLING            : boolean := true
    );
    port (
        clk                     : in std_logic;   
        rst                     : in std_logic;   
        rx                      : in std_logic;   
        tx                      : in std_logic;   
        -- Output signals from this module 
        sample_point            : out std_logic;   
        sampled_bit             : out std_logic;   
        sampled_bit_q           : out std_logic;   
        tx_point                : out std_logic;   
        hard_sync               : out std_logic;   
        -- Output from can_bsp module 
        rx_idle                 : in std_logic;   
        rx_inter                : in std_logic;   
        transmitting            : in std_logic;   
        transmitter             : in std_logic;   
        go_rx_inter             : in std_logic;   
        tx_next                 : in std_logic;   
        go_overload_frame       : in std_logic;   
        go_error_frame          : in std_logic;   
        go_tx                   : in std_logic;   
        send_ack                : in std_logic;   
        node_error_passive      : in std_logic
    );   
end entity CanLiteBitTimingLogic;

architecture Behavioral of CanLiteBitTimingLogic is

    function conv_std_logic(b : boolean) return std_ulogic is
    begin
        if b then return('1'); else return('0'); end if;
    end;

    signal clk_cnt                  :  unsigned(6 downto 0);   
    signal clk_en                   :  std_logic;   
    signal clk_en_q                 :  std_logic;   
    signal sync_blocked             :  std_logic;   
    signal hard_sync_blocked        :  std_logic;   
    signal quant_cnt                :  unsigned(4 downto 0);   
    signal delay                    :  unsigned(3 downto 0);   
    signal sync                     :  std_logic;   
    signal seg1                     :  std_logic;   
    signal seg2                     :  std_logic;   
    signal resync_latched           :  std_logic;   
    signal sample                   :  std_logic_vector(1 downto 0);   
    signal tx_next_sp               :  std_logic;   
    signal go_sync                  :  std_logic;   
    signal go_seg1                  :  std_logic;   
    signal go_seg2                  :  std_logic;   
    signal preset_cnt               :  unsigned(7 downto 0);   
    signal sync_window              :  std_logic;   
    signal resync                   :  std_logic;    
    signal sample_point_xhdl1       :  std_logic;   
    signal sampled_bit_xhdl2        :  std_logic;   
    signal sampled_bit_q_xhdl3      :  std_logic;   
    signal tx_point_xhdl4           :  std_logic;   
    signal hard_sync_xhdl5          :  std_logic;   

begin
   sample_point <= sample_point_xhdl1;
   sampled_bit <= sampled_bit_xhdl2;
   sampled_bit_q <= sampled_bit_q_xhdl3;
   tx_point <= tx_point_xhdl4;
   hard_sync <= hard_sync_xhdl5;
   preset_cnt <=  to_unsigned(BAUD_RATE_PRESCALAR, 7) & '0';
   hard_sync_xhdl5 <= (((rx_idle or rx_inter) and (not rx)) and sampled_bit_xhdl2) and (not hard_sync_blocked);
   resync <= ((((not rx_idle) and (not rx_inter)) and (not rx)) and sampled_bit_xhdl2) and (not sync_blocked);

    -- Generating general enable signal that defines baud rate. 
    process (clk, rst)
    begin
      if (rst = '1') then
         clk_cnt <= b"0000000";    
      elsif rising_edge(clk) then
         if (('0' & clk_cnt) >= (preset_cnt - 1)) then
            clk_cnt <= b"0000000" ;    
         else
            clk_cnt <= clk_cnt + 1;
         end if;
      end if;
    end process;

   process (clk, rst)
   begin
      if (rst = '1') then
         clk_en <= '0';    
      elsif rising_edge(clk) then
         if (('0' & clk_cnt) = (preset_cnt - "00000001")) then
            clk_en <= '1' ;    
         else
            clk_en <= '0' ;    
         end if;
      end if;
   end process;

   process (clk, rst)
   begin
      if (rst = '1') then
         clk_en_q <= '0';    
      elsif rising_edge(clk) then
         clk_en_q <= clk_en ;    
      end if;
   end process;
   
   -- Changing states 
   go_sync <= (((clk_en_q and seg2) and CONV_STD_LOGIC(quant_cnt(2 downto 0) = (TIME_SEGMENT_2 - 1))) and (not hard_sync_xhdl5)) and (not resync) ;
   go_seg1 <= clk_en_q and (sync or hard_sync_xhdl5 or ((resync and seg2) and sync_window) or (resync_latched and sync_window)) ;
   go_seg2 <= clk_en_q and ((seg1 and (not hard_sync_xhdl5)) and CONV_STD_LOGIC(quant_cnt = ( '0' & (TIME_SEGMENT_1 - 1 + delay)))) ;

   process (clk, rst)
   begin
      if (rst = '1') then
         tx_point_xhdl4 <= '0';    
      elsif rising_edge(clk) then
         tx_point_xhdl4 <= (not tx_point_xhdl4 and seg2) and ((clk_en and CONV_STD_LOGIC(quant_cnt(2 downto 0) = (TIME_SEGMENT_2 - 1))) or ((clk_en or clk_en_q) and (resync or hard_sync_xhdl5))) ;    --  When transmitter we should transmit as soon as possible.
      end if;
   end process;

   -- When early edge is detected outside of the SJW field, synchronization request is latched and performed when
   --  When early edge is detected outside of the SJW field, synchronization request is latched and performed when
   --    SJW is reached 
   
   process (clk, rst)
   begin
      if (rst = '1') then
         resync_latched <= '0';    
      elsif rising_edge(clk) then
         if (((resync and seg2) and (not sync_window)) = '1') then
            resync_latched <= '1' ;    
         else
            if (go_seg1 = '1') then
               resync_latched <= '0';    
            end if;
         end if;
      end if;
   end process;

   -- Synchronization stage/segment 
   process (clk, rst)
   begin
      if (rst = '1') then
         sync <= '0';    
      elsif rising_edge(clk) then
         if (clk_en_q = '1') then
            sync <= go_sync ;    
         end if;
      end if;
   end process;

   -- Seg1 stage/segment (together with propagation segment which is 1 quant long) 
   process (clk, rst)
   begin
      if (rst = '1') then
         seg1 <= '1';    
      elsif rising_edge(clk) then
         if (go_seg1 = '1') then
            seg1 <= '1' ;    
         else
            if (go_seg2 = '1') then
               seg1 <= '0' ;    
            end if;
         end if;
      end if;
   end process;

   -- Seg2 stage/segment 
   process (clk, rst)
   begin
      if (rst = '1') then
         seg2 <= '0';    
      elsif rising_edge(clk) then
         if (go_seg2 = '1') then
            seg2 <= '1' ;    
         else
            if ((go_sync or go_seg1) = '1') then
               seg2 <= '0' ;    
            end if;
         end if;
      end if;
   end process;

   -- Quant counter 
   process (clk, rst)
   begin
      if (rst = '1') then
         quant_cnt <= "00000";    
      elsif rising_edge(clk) then
         if ((go_sync or go_seg1 or go_seg2) = '1') then
            quant_cnt <= "00000" ;    
         else
            if (clk_en_q = '1') then
               quant_cnt <= quant_cnt + "00001" ;    
            end if;
         end if;
      end if;
   end process;

   -- When late edge is detected (in seg1 stage), stage seg1 is prolonged. 
   process (clk, rst)
   begin
      if (rst = '1') then
         delay <= (others => '0');
      elsif rising_edge(clk) then
         if (((resync and seg1) and (not transmitting or (transmitting and (tx_next_sp or (tx and (not rx)))))) = '1') then
            if quant_cnt > (SYNCHRONIZATION_JUMP_WIDTH - 1) then
                delay <= to_unsigned(SYNCHRONIZATION_JUMP_WIDTH, 4);
            else
                delay <= quant_cnt(3 downto 0) + 1;
            end if;
         else
            if ((go_sync or go_seg1) = '1') then
                delay <= (others => '0');
            end if;
         end if;
      end if;
   end process;
   -- If early edge appears within this window (in seg2 stage), phase error is fully compensated
   sync_window <= CONV_STD_LOGIC((to_unsigned(TIME_SEGMENT_2 - 1, 5) - quant_cnt(2 downto 0)) < SYNCHRONIZATION_JUMP_WIDTH) ;

   -- Sampling data (remembering two samples all the time).
   process (clk, rst)
   begin
      if (rst = '1') then
         sample <= "11";    
      elsif rising_edge(clk) then
         if (clk_en_q = '1') then
            sample <= sample(0) & rx;    
         end if;
      end if;
   end process;

   -- When enabled, triple sampling is done here.
   process (clk, rst)
   begin
      if (rst = '1') then
         sampled_bit_xhdl2 <= '1';    
         sampled_bit_q_xhdl3 <= '1';    
         sample_point_xhdl1 <= '0';    
      elsif rising_edge(clk) then
         if (go_error_frame = '1') then
            sampled_bit_q_xhdl3 <= sampled_bit_xhdl2 ;    
            sample_point_xhdl1 <= '0' ;    
         else
            if ((clk_en_q and (not hard_sync_xhdl5)) = '1') then
               if ((seg1 and CONV_STD_LOGIC(quant_cnt = ('0' & ((TIME_SEGMENT_1 - 1) + delay)))) = '1') then
                  sample_point_xhdl1 <= '1' ;    
                  sampled_bit_q_xhdl3 <= sampled_bit_xhdl2 ;    
                  if TRIPLE_SAMPLING then
                     sampled_bit_xhdl2 <= (sample(0) and sample(1)) or (sample(0) and rx) or (sample(1) and rx) ;    
                  else
                     sampled_bit_xhdl2 <= rx ;    
                  end if;
               end if;
            else
               sample_point_xhdl1 <= '0' ;    
            end if;
         end if;
      end if;
   end process;

   -- tx_next_sp shows next value that will be driven on the TX. When driving 1 and receiving 0 we
   -- need to synchronize (even when we are a transmitter)
   
   process (clk, rst)
   begin
      if (rst = '1') then
         tx_next_sp <= '0';    
      elsif rising_edge(clk) then
         if ((go_overload_frame or (go_error_frame and (not node_error_passive)) or go_tx or send_ack) = '1') then
            tx_next_sp <= '0' ;    
         else
            if ((go_error_frame and node_error_passive) = '1') then
               tx_next_sp <= '1' ;    
            else
               if (sample_point_xhdl1 = '1') then
                  tx_next_sp <= tx_next ;    
               end if;
            end if;
         end if;
      end if;
   end process;

   -- Blocking synchronization (can occur only once in a bit time) 
   process (clk, rst)
   begin
      if (rst = '1') then
         sync_blocked <= '1' ;    
      elsif rising_edge(clk) then
         if (clk_en_q = '1') then
            if (resync = '1') then
               sync_blocked <= '1' ;    
            else
               if (go_seg2 = '1') then
                  sync_blocked <= '0' ;    
               end if;
            end if;
         end if;
      end if;
   end process;

   -- Blocking hard synchronization when occurs once or when we are transmitting a msg 
   process (clk, rst)
   begin
      if (rst = '1') then
         hard_sync_blocked <= '0' ;    
      elsif rising_edge(clk) then
         if (((hard_sync_xhdl5 and clk_en_q) or ((((transmitting and transmitter) or go_tx) and tx_point_xhdl4) and (not tx_next))) = '1') then
            hard_sync_blocked <= '1' ;    
         else
            if ((go_rx_inter or (((rx_idle or rx_inter) and sample_point_xhdl1) and sampled_bit_xhdl2)) = '1') then
               -- When a glitch performed synchronization
               
               hard_sync_blocked <= '0' ;    
            end if;
         end if;
      end if;
   end process;

end architecture Behavioral;


library ieee;
use ieee.std_logic_1164.all;

entity CanLiteCrc is
    port (
        clk                     : in std_logic;   
        data                    : in std_logic;   
        enable                  : in std_logic;   
        initialize              : in std_logic;   
        crc                     : out std_logic_vector(14 downto 0)
    );   
end entity CanLiteCrc;

architecture Behavioral of CanLiteCrc is

    signal Crc_q    :  std_logic_vector(14 downto 0);   
    signal NextBit  :  std_logic;   

begin
   crc <= Crc_q;
   NextBit <= data xor Crc_q(14) ;

   process (clk)
   begin
      if rising_edge(clk) then
         if (initialize = '1') then
            Crc_q <= (others => '0');
         else
            if (enable = '1') then
               if (NextBit = '1') then
                  Crc_q <= (Crc_q(13 downto 0) & '0') xor b"100010110011001"; --! CRC-15-CAN: x"4599"
               else
                  Crc_q <= (Crc_q(13 downto 0) & '0');    
               end if;
            end if;
         end if;
      end if;
   end process;

end architecture Behavioral;

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_misc.all;
use ieee.numeric_std.all;
use work.CanBus;

entity CanLiteBitStreamProcessor is
    port (
        clk                     : in std_logic;   
        rst                     : in std_logic;   
        sample_point            : in std_logic;   
        sampled_bit             : in std_logic;   
        sampled_bit_q           : in std_logic;   
        tx_point                : in std_logic;   
        hard_sync               : in std_logic;    
        reset_mode              : in std_logic;   
        tx_request              : in std_logic;
        TxFrame                 : in  CanBus.Frame;
        RxFrame                 : out CanBus.Frame;
        tx_state                : out std_logic;   
        tx_state_q              : out std_logic;   
        rx_idle                 : out std_logic;
        transmitting            : out std_logic;
        transmitter             : out std_logic;
        go_rx_inter             : out std_logic;
        not_first_bit_of_inter  : out std_logic;
        rx_inter                : out std_logic;
        set_reset_mode          : out std_logic;
        node_bus_off            : out std_logic;
        error_status            : out std_logic;
        rx_err_cnt              : out unsigned(7 downto 0);
        tx_err_cnt              : out unsigned(7 downto 0);
        transmit_status         : out std_logic;
        receive_status          : out std_logic;
        tx_successful           : out std_logic;
        need_to_tx              : out std_logic;
        node_error_passive      : out std_logic;
        tx                      : out std_logic;
        tx_next                 : out std_logic;
        go_overload_frame       : out std_logic;
        go_error_frame          : out std_logic;
        go_tx                   : out std_logic;
        send_ack                : out std_logic
    );   
end entity CanLiteBitStreamProcessor;

architecture Behavioral of CanLiteBitStreamProcessor is

    function conv_std_logic(b : boolean) return std_ulogic is
    begin
        if b then return('1'); else return('0'); end if;
    end;
    
    function Reverse(X: std_logic_vector) return std_logic_vector is
        alias XReversed : std_logic_vector(X'reverse_range) is X;
        variable Y      : std_logic_vector(X'range);
    begin
        for i in XReversed'range loop
            Y(i) := XReversed(i);
        end loop;
        return Y;
    end function Reverse;

    component CanLiteCrc
        port (
            clk                     : in  std_logic;
            data                    : in  std_logic;
            enable                  : in  std_logic;
            initialize              : in  std_logic;
            crc                     : out std_logic_vector(14 downto 0)
        );
    end component CanLiteCrc;

   ------------------------------
    signal reset_mode_q             :  std_logic;   
    signal bit_cnt                  :  unsigned(5 downto 0);   
    signal RxDlc                    :  std_logic_vector(3 downto 0);
    signal RxId                     :  std_logic_vector(10 downto 0);   
    signal bit_stuff_cnt            :  unsigned(2 downto 0);   
    signal bit_stuff_cnt_tx         :  unsigned(2 downto 0);   
    signal tx_point_q               :  std_logic;   
    signal rx_id1                   :  std_logic;   
    signal rx_rtr                   :  std_logic;   
    signal rx_ide                   :  std_logic;   
    signal rx_r0                    :  std_logic;   
    signal rx_dlc                   :  std_logic;   
    signal rx_data                  :  std_logic;   
    signal rx_crc                   :  std_logic;   
    signal rx_crc_lim               :  std_logic;   
    signal rx_ack                   :  std_logic;   
    signal rx_ack_lim               :  std_logic;   
    signal rx_eof                   :  std_logic;   
    signal go_early_tx_latched      :  std_logic;   
    signal RxRtr                    :  std_logic;   
    signal RxIde                    :  std_logic;   
    signal crc_in                   :  std_logic_vector(14 downto 0);   
    signal RxDataByte               :  std_logic_vector(7 downto 0);
    signal write_data_to_tmp_fifo   :  std_logic;   
    signal byte_cnt                 :  unsigned(2 downto 0);   
    signal bit_stuff_cnt_en         :  std_logic;   
    signal crc_enable               :  std_logic;   
    signal eof_cnt                  :  unsigned(2 downto 0);   
    signal passive_cnt              :  unsigned(2 downto 0);   
    signal error_frame              :  std_logic;   
    signal enable_error_cnt2        :  std_logic;   
    signal error_cnt1               :  unsigned(2 downto 0);   
    signal error_cnt2               :  unsigned(2 downto 0);   
    signal delayed_dominant_cnt     :  unsigned(2 downto 0);   
    signal enable_overload_cnt2     :  std_logic;   
    signal overload_frame_blocked   :  std_logic;   
    signal overload_request_cnt     :  unsigned(1 downto 0);   
    signal overload_cnt1            :  unsigned(2 downto 0);   
    signal overload_cnt2            :  unsigned(2 downto 0);   
    signal crc_err                  :  std_logic;   
    signal arbitration_lost         :  std_logic; 
    signal arbitration_field_d      :  std_logic;
    signal arbitration_cnt          :  unsigned(4 downto 0);     
    signal tx_q                     :  std_logic;   
    signal data_cnt                 :  unsigned(3 downto 0);   --  Counting the data bytes that are written to FIFO
    signal wr_fifo                  :  std_logic;   --  Write data and header to 64-byte fifo
    signal data_for_fifo            :  std_logic_vector(7 downto 0);   --  Multiplexed data that is stored to 64-byte fifo
    signal tx_pointer               :  unsigned(5 downto 0);   
    signal tx_bit                   :  std_logic;   
    signal finish_msg               :  std_logic;   
    signal bus_free_cnt             :  unsigned(3 downto 0);   
    signal bus_free_cnt_en          :  std_logic;   
    signal bus_free                 :  std_logic;   
    signal waiting_for_bus_free     :  std_logic;   
    signal node_bus_off_q           :  std_logic;   
    signal ack_err_latched          :  std_logic;   
    signal bit_err_latched          :  std_logic;   
    signal stuff_err_latched        :  std_logic;   
    signal form_err_latched         :  std_logic;   
    signal rule3_exc1_1             :  std_logic;   
    signal rule3_exc1_2             :  std_logic;   
    signal suspend                  :  std_logic;   
    signal susp_cnt_en              :  std_logic;   
    signal susp_cnt                 :  unsigned(2 downto 0);   
    signal error_flag_over_latched  :  std_logic;   
    signal first_compare_bit        :  std_logic;   
    signal bit_de_stuff             :  std_logic;   
    signal bit_de_stuff_tx          :  std_logic;   
    signal rule5                    :  std_logic;   
   -- Rx state machine 
    signal go_rx_idle               :  std_logic;   
    signal go_rx_id1                :  std_logic;   
    signal go_rx_rtr               :  std_logic;   
    signal go_rx_ide                :  std_logic;     
    signal go_rx_r0                 :  std_logic;   
    signal go_rx_dlc                :  std_logic;   
    signal go_rx_data               :  std_logic;   
    signal go_rx_crc                :  std_logic;   
    signal go_rx_crc_lim            :  std_logic;   
    signal go_rx_ack                :  std_logic;   
    signal go_rx_ack_lim            :  std_logic;   
    signal go_rx_eof                :  std_logic;   
    signal last_bit_of_inter        :  std_logic;   
    signal go_crc_enable            :  std_logic;   
    signal rst_crc_enable           :  std_logic;   
    signal bit_de_stuff_set         :  std_logic;   
    signal bit_de_stuff_reset       :  std_logic;   
    signal go_early_tx              :  std_logic;   
    signal calculated_crc           :  std_logic_vector(14 downto 0);  
    signal remote_rq                :  std_logic;   
    signal RxDataLength             :  unsigned(3 downto 0);   
    signal form_err                 :  std_logic;   
    signal error_frame_ended        :  std_logic;   
    signal overload_frame_ended     :  std_logic;   
    signal bit_err                  :  std_logic;   
    signal ack_err                  :  std_logic;   
    signal stuff_err                :  std_logic;
    signal reset_wr_fifo            :  std_logic;
    signal err                      :  std_logic;
    signal arbitration_field        :  std_logic;
    signal basic_chain              :  std_logic_vector(18 downto 0);
    signal basic_chain_data         :  std_logic_vector(63 downto 0);
    signal BasicChainReversed       :  std_logic_vector(0 to 18);
    signal BasicChainDataReversed   :  std_logic_vector(0 to 63);
  
    signal rst_tx_pointer           :  std_logic;    
    signal bit_err_exc1             :  std_logic;   
    signal bit_err_exc2             :  std_logic;   
    signal bit_err_exc3             :  std_logic;   
    signal bit_err_exc4             :  std_logic;   
    signal bit_err_exc5             :  std_logic;   
    signal bit_err_exc6             :  std_logic;   
    signal error_flag_over          :  std_logic;   
    signal overload_flag_over       :  std_logic;    
    signal limited_tx_cnt_std       :  unsigned(5 downto 0);   

    signal CrcEnableValid           :  std_logic;   
             
    signal tx_state_xhdl2           :  std_logic;   
    signal tx_state_q_xhdl3         :  std_logic;   
    signal overload_frame_xhdl4     :  std_logic;   
    signal rx_idle_xhdl6            :  std_logic;   
    signal transmitting_q           :  std_logic;   
    signal transmitter_xhdl8        :  std_logic;   
    signal go_rx_inter_xhdl9        :  std_logic;   
    signal not_first_bit_of_inter_xhdl10   :  std_logic;   
    signal rx_inter_xhdl11          :  std_logic;   
    signal set_reset_mode_xhdl12    :  std_logic;   
    signal node_bus_off_xhdl13      :  std_logic;   
    signal rx_err_cnt_xhdl15        :  unsigned(8 downto 0);   
    signal tx_err_cnt_xhdl16        :  unsigned(8 downto 0);     
    signal tx_successful_xhdl19     :  std_logic;   
    signal need_to_tx_xhdl20        :  std_logic;        
    signal node_error_passive_xhdl26:  std_logic;      
    signal tx_xhdl29                :  std_logic;   
    signal tx_next_xhdl30           :  std_logic;   
    signal go_overload_frame_xhdl32 :  std_logic;   
    signal go_error_frame_xhdl33    :  std_logic;   
    signal go_tx_xhdl34             :  std_logic;   
    signal send_ack_xhdl35          :  std_logic;   
 

begin
    RxFrame.Id <= RxId;
    RxFrame.Rtr <= RxRtr;
    RxFrame.Dlc <= RxDlc;
    
    tx_state <= tx_state_xhdl2;
    tx_state_q <= tx_state_q_xhdl3;
    rx_idle <= rx_idle_xhdl6;
    transmitting <= transmitting_q;
    transmitter <= transmitter_xhdl8;
    go_rx_inter <= go_rx_inter_xhdl9;
    not_first_bit_of_inter <= not_first_bit_of_inter_xhdl10;
    rx_inter <= rx_inter_xhdl11;
    set_reset_mode <= set_reset_mode_xhdl12;
    node_bus_off <= node_bus_off_xhdl13;
    error_status <= '1' when (rx_err_cnt_xhdl15 > 96) or (tx_err_cnt_xhdl16 > 96) else '0';
    rx_err_cnt <= rx_err_cnt_xhdl15(7 downto 0);
    tx_err_cnt <= tx_err_cnt_xhdl16(7 downto 0);
    transmit_status <= transmitting_q;
    receive_status <= ((not waiting_for_bus_free) and (not rx_idle_xhdl6)) and (not transmitting_q);
    tx_successful <= tx_successful_xhdl19;
    need_to_tx <= need_to_tx_xhdl20;
    node_error_passive <= node_error_passive_xhdl26;
    tx <= tx_xhdl29;
    tx_next <= tx_next_xhdl30;
    go_overload_frame <= go_overload_frame_xhdl32;
    go_error_frame <= go_error_frame_xhdl33;
    go_tx <= go_tx_xhdl34;
    send_ack <= send_ack_xhdl35;    
    
    go_rx_idle <= ((sample_point and sampled_bit) and last_bit_of_inter) or (bus_free and (not node_bus_off_xhdl13)) ;
    go_rx_id1 <= (sample_point and (not sampled_bit)) and (rx_idle_xhdl6 or last_bit_of_inter) ;
    go_rx_rtr <= (((not bit_de_stuff) and sample_point) and rx_id1) and CONV_STD_LOGIC(bit_cnt(3 downto 0) = b"1010") ;
    go_rx_ide <= ((not bit_de_stuff) and sample_point) and rx_rtr ;
    go_rx_r0 <= ((not bit_de_stuff) and sample_point) and (rx_ide and (not sampled_bit));
    go_rx_dlc <= ((not bit_de_stuff) and sample_point) and rx_r0 ;
    go_rx_data <= (((((not bit_de_stuff) and sample_point) and rx_dlc) and and_reduce(std_logic_vector(bit_cnt(1 downto 0)))) and (sampled_bit or (or_reduce(RxDlc(2 downto 0))))) and (not remote_rq) ;
    go_rx_crc <= ((not bit_de_stuff) and sample_point) and (((rx_dlc and and_reduce(std_logic_vector(bit_cnt(1 downto 0)))) and (((not sampled_bit) and (not (or_reduce(RxDlc(2 downto 0))))) or remote_rq)) or (rx_data and CONV_STD_LOGIC(bit_cnt(5 downto 0) = ((RxDataLength & b"000") - 1)))) ;
    go_rx_crc_lim <= (((not bit_de_stuff) and sample_point) and rx_crc) and CONV_STD_LOGIC(bit_cnt(3 downto 0) = b"1110") ;
    go_rx_ack <= ((not bit_de_stuff) and sample_point) and rx_crc_lim ;
    go_rx_ack_lim <= sample_point and rx_ack ;
    go_rx_eof <= sample_point and rx_ack_lim ;
    go_rx_inter_xhdl9 <= (((sample_point and rx_eof) and CONV_STD_LOGIC(eof_cnt = b"110")) or error_frame_ended or overload_frame_ended);
    go_error_frame_xhdl33 <= form_err or stuff_err or bit_err or ack_err or (crc_err and go_rx_eof) ;
    error_frame_ended <= CONV_STD_LOGIC(error_cnt2 = "111") and tx_point ;
    overload_frame_ended <= CONV_STD_LOGIC(overload_cnt2 = "111") and tx_point ;
    go_overload_frame_xhdl32 <= (((sample_point and ((not sampled_bit))) and (((rx_eof and (not transmitter_xhdl8)) and CONV_STD_LOGIC(eof_cnt = "110")) or error_frame_ended or overload_frame_ended)) or (((sample_point and (not sampled_bit)) and rx_inter_xhdl11) and CONV_STD_LOGIC(bit_cnt(1 downto 0) < "10")) or ((sample_point and (not sampled_bit)) and CONV_STD_LOGIC((error_cnt2 = "111") or (overload_cnt2 = b"111"))));
    go_crc_enable <= hard_sync or go_tx_xhdl34 ;
    rst_crc_enable <= go_rx_crc ;
    bit_de_stuff_set <= go_rx_id1 and (not go_error_frame_xhdl33) ;
    bit_de_stuff_reset <= go_rx_ack or go_error_frame_xhdl33 or go_overload_frame_xhdl32 ;
    remote_rq <= ((not RxIde) and RxRtr);
    RxDataLength <= unsigned(RxDlc) when RxDlc(3) = '0' else b"1000";
    ack_err <= (((rx_ack and sample_point) and sampled_bit) and tx_state_xhdl2);
    bit_err <= ((((((((tx_state_xhdl2 or error_frame or overload_frame_xhdl4 or rx_ack) and sample_point) and CONV_STD_LOGIC(tx_xhdl29 /= sampled_bit)) and (not bit_err_exc1)) and (not bit_err_exc2)) and (not bit_err_exc3)) and (not bit_err_exc4)) and (not bit_err_exc5)) and (not bit_err_exc6) and (not reset_mode);
    bit_err_exc1 <= (tx_state_xhdl2 and arbitration_field) and tx_xhdl29 ;
    bit_err_exc2 <= rx_ack and tx_xhdl29 ;
    bit_err_exc3 <= (error_frame and node_error_passive_xhdl26) and CONV_STD_LOGIC(error_cnt1 < "111") ;
    bit_err_exc4 <= ((error_frame and CONV_STD_LOGIC(error_cnt1 = "111")) and (not enable_error_cnt2)) or ((overload_frame_xhdl4 and CONV_STD_LOGIC(overload_cnt1 = "111")) and (not enable_overload_cnt2)) ;
    bit_err_exc5 <= (error_frame and CONV_STD_LOGIC(error_cnt2 = "111")) or (overload_frame_xhdl4 and CONV_STD_LOGIC(overload_cnt2 = "111")) ;
    bit_err_exc6 <= (CONV_STD_LOGIC(eof_cnt = "110") and rx_eof) and (not transmitter_xhdl8) ;
    arbitration_field <= rx_id1 or rx_rtr or rx_ide;
    last_bit_of_inter <= rx_inter_xhdl11 and CONV_STD_LOGIC(bit_cnt(1 downto 0) = "10") ;
    not_first_bit_of_inter_xhdl10 <= rx_inter_xhdl11 and CONV_STD_LOGIC(bit_cnt(1 downto 0) /= "00") ;

   -- Rx idle state
   process (clk, rst)
   begin
      if (rst = '1') then
         rx_idle_xhdl6 <= '0';    
      elsif rising_edge(clk) then
         if ((go_rx_id1 or go_error_frame_xhdl33) = '1') then
            rx_idle_xhdl6 <= '0' ;    
         else
            if (go_rx_idle = '1') then
               rx_idle_xhdl6 <= '1' ;    
            end if;
         end if;
      end if;
   end process;

   -- Rx id1 state
   process (clk, rst)
   begin
      if (rst = '1') then
         rx_id1 <= '0';    
      elsif rising_edge(clk) then
         if ((go_rx_rtr or go_error_frame_xhdl33) = '1') then
            rx_id1 <= '0' ;    
         else
            if (go_rx_id1 = '1') then
               rx_id1 <= '1' ;    
            end if;
         end if;
      end if;
   end process;

   -- Rx rtr state
   process (clk, rst)
   begin
      if (rst = '1') then
         rx_rtr <= '0';    
      elsif rising_edge(clk) then
         if ((go_rx_ide or go_error_frame_xhdl33) = '1') then
            rx_rtr <= '0' ;    
         else
            if (go_rx_rtr = '1') then
               rx_rtr <= '1' ;    
            end if;
         end if;
      end if;
   end process;

   -- Rx ide state
   process (clk, rst)
   begin
      if (rst = '1') then
         rx_ide <= '0';    
      elsif rising_edge(clk) then
         if ((go_rx_r0 or go_error_frame_xhdl33) = '1') then
            rx_ide <= '0' ;    
         else
            if (go_rx_ide = '1') then
               rx_ide <= '1' ;    
            end if;
         end if;
      end if;
   end process;

   -- Rx r0 state
   process (clk, rst)
   begin
      if (rst = '1') then
         rx_r0 <= '0';    
      elsif rising_edge(clk) then
         if ((go_rx_dlc or go_error_frame_xhdl33) = '1') then
            rx_r0 <= '0' ;    
         else
            if (go_rx_r0 = '1') then
               rx_r0 <= '1' ;    
            end if;
         end if;
      end if;
   end process;

   -- Rx dlc state
   process (clk, rst)
   begin
      if (rst = '1') then
         rx_dlc <= '0';    
      elsif rising_edge(clk) then
         if ((go_rx_data or go_rx_crc or go_error_frame_xhdl33) = '1') then
            rx_dlc <= '0' ;    
         else
            if (go_rx_dlc = '1') then
               rx_dlc <= '1' ;    
            end if;
         end if;
      end if;
   end process;

   -- Rx data state
   process (clk, rst)
   begin
      if (rst = '1') then
         rx_data <= '0';    
      elsif rising_edge(clk) then
         if ((go_rx_crc or go_error_frame_xhdl33) = '1') then
            rx_data <= '0' ;    
         else
            if (go_rx_data = '1') then
               rx_data <= '1' ;    
            end if;
         end if;
      end if;
   end process;

   -- Rx crc state
   process (clk, rst)
   begin
      if (rst = '1') then
         rx_crc <= '0';    
      elsif rising_edge(clk) then
         if ((go_rx_crc_lim or go_error_frame_xhdl33) = '1') then
            rx_crc <= '0' ;    
         else
            if (go_rx_crc = '1') then
               rx_crc <= '1' ;    
            end if;
         end if;
      end if;
   end process;

   -- Rx crc delimiter state
   process (clk, rst)
   begin
      if (rst = '1') then
         rx_crc_lim <= '0';    
      elsif rising_edge(clk) then
         if ((go_rx_ack or go_error_frame_xhdl33) = '1') then
            rx_crc_lim <= '0' ;    
         else
            if (go_rx_crc_lim = '1') then
               rx_crc_lim <= '1' ;    
            end if;
         end if;
      end if;
   end process;

   -- Rx ack state
   process (clk, rst)
   begin
      if (rst = '1') then
         rx_ack <= '0';    
      elsif rising_edge(clk) then
         if ((go_rx_ack_lim or go_error_frame_xhdl33) = '1') then
            rx_ack <= '0' ;    
         else
            if (go_rx_ack = '1') then
               rx_ack <= '1' ;    
            end if;
         end if;
      end if;
   end process;

   -- Rx ack delimiter state
   process (clk, rst)
   begin
      if (rst = '1') then
         rx_ack_lim <= '0';    
      elsif rising_edge(clk) then
         if ((go_rx_eof or go_error_frame_xhdl33) = '1') then
            rx_ack_lim <= '0' ;    
         else
            if (go_rx_ack_lim = '1') then
               rx_ack_lim <= '1' ;    
            end if;
         end if;
      end if;
   end process;

   -- Rx eof state
   process (clk, rst)
   begin
      if (rst = '1') then
         rx_eof <= '0';    
      elsif rising_edge(clk) then
         if ((go_rx_inter_xhdl9 or go_error_frame_xhdl33 or go_overload_frame_xhdl32) = '1') then
            rx_eof <= '0' ;    
         else
            if (go_rx_eof = '1') then
               rx_eof <= '1' ;    
            end if;
         end if;
      end if;
   end process;

   -- Interframe space
   process (clk, rst)
   begin
      if (rst = '1') then
         rx_inter_xhdl11 <= '0';    
      elsif rising_edge(clk) then
         if ((go_rx_idle or go_rx_id1 or go_overload_frame_xhdl32 or go_error_frame_xhdl33) = '1') then
            rx_inter_xhdl11 <= '0' ;    
         else
            if (go_rx_inter_xhdl9 = '1') then
               rx_inter_xhdl11 <= '1' ;    
            end if;
         end if;
      end if;
   end process;

   -- ID register
   process (clk, rst)
   begin
      if (rst = '1') then
         RxId <= (others => '0');    
      elsif rising_edge(clk) then
         if (((sample_point and rx_id1) and (not bit_de_stuff)) = '1') then
               RxId <= RxId(9 downto 0) & sampled_bit ;    
         end if;
      end if;
   end process;

   -- rtr bit
   process (clk, rst)
   begin
      if (rst = '1') then
         RxRtr <= '0';    
      elsif rising_edge(clk) then
         if (((sample_point and rx_rtr) and (not bit_de_stuff)) = '1') then
            RxRtr <= sampled_bit ;    
         end if;
      end if;
   end process;

   -- ide bit
   process (clk, rst)
   begin
      if (rst = '1') then
         RxIde <= '0';    
      elsif rising_edge(clk) then
         if (((sample_point and rx_ide) and (not bit_de_stuff)) = '1') then
            RxIde <= sampled_bit;
         end if;
      end if;
   end process;

   -- Data length
   process (clk, rst)
   begin
      if (rst = '1') then
         RxDlc <= (others => '0');    
      elsif rising_edge(clk) then
         if (((sample_point and rx_dlc) and (not bit_de_stuff)) = '1') then
            RxDlc <= RxDlc(2 downto 0) & sampled_bit ;    
         end if;
      end if;
   end process;

   -- Data
   process (clk, rst)
   begin
      if (rst = '1') then
         RxDataByte <= (others => '0');    
      elsif rising_edge(clk) then
            if (((sample_point and rx_data) and (not bit_de_stuff)) = '1') then
               RxDataByte <= RxDataByte(6 downto 0) & sampled_bit;
            end if;
       end if;
   end process;

   process (clk, rst)
   begin
      if (rst = '1') then
         write_data_to_tmp_fifo <= '0';    
      elsif rising_edge(clk) then
            if ((((sample_point and rx_data) and (not bit_de_stuff)) and (and_reduce(std_logic_vector(bit_cnt(2 downto 0))))) = '1') then
               write_data_to_tmp_fifo <= '1' ;    
            else
               write_data_to_tmp_fifo <= '0' ;    
            end if;
      end if;
   end process;

   process (clk, rst)
   begin
      if (rst = '1') then
         byte_cnt <= (others => '0');    
      elsif rising_edge(clk) then
            if (write_data_to_tmp_fifo = '1') then
               byte_cnt <= byte_cnt + 1;
            else
               if ((sample_point and go_rx_crc_lim) = '1') then
                  byte_cnt <= (others => '0');
               end if;
            end if;
      end if;
   end process;

    process (clk, rst)
    begin
        if rst = '1' then
            RxFrame.Data <= (others => (others => '0'));
        elsif rising_edge(clk) then
            if (write_data_to_tmp_fifo = '1') then
                RxFrame.Data(to_integer(byte_cnt)) <= RxDataByte;
            end if;
        end if;
    end process;

   -- CRC
   process (clk, rst)
   begin
      if (rst = '1') then
         crc_in <= "000000000000000";    
      elsif rising_edge(clk) then
            if (((sample_point and rx_crc) and (not bit_de_stuff)) = '1') then
               crc_in <= crc_in(13 downto 0) & sampled_bit ;    
            end if;
      end if;
   end process;

   -- bit_cnt
   process (clk, rst)
   begin
      if (rst = '1') then
         bit_cnt <= "000000";    
      elsif rising_edge(clk) then
            if ((go_rx_id1 or go_rx_dlc or go_rx_data or go_rx_crc or go_rx_ack or go_rx_eof or go_rx_inter_xhdl9 or go_error_frame_xhdl33 or go_overload_frame_xhdl32) = '1') then
               bit_cnt <= (others => '0');
            else
               if ((sample_point and (not bit_de_stuff)) = '1') then
                  bit_cnt <= bit_cnt + 1;
               end if;
         end if;
      end if;
   end process;

   -- eof_cnt
   process (clk, rst)
   begin
      if (rst = '1') then
         eof_cnt <= "000";    
      elsif rising_edge(clk) then
            if (sample_point = '1') then
               if ((go_rx_inter_xhdl9 or go_error_frame_xhdl33 or go_overload_frame_xhdl32) = '1') then
                  eof_cnt <= "000" ;    
               else
                  if (rx_eof = '1') then
                     eof_cnt <= eof_cnt + "001" ;    
                  end if;
               end if;
         end if;
      end if;
   end process;

   -- Enabling bit de-stuffing
   process (clk, rst)
   begin
      if (rst = '1') then
         bit_stuff_cnt_en <= '0';    
      elsif rising_edge(clk) then
            if (bit_de_stuff_set = '1') then
               bit_stuff_cnt_en <= '1' ;    
            else
               if (bit_de_stuff_reset = '1') then
                  bit_stuff_cnt_en <= '0' ;    
               end if;
         end if;
      end if;
   end process;

   -- bit_stuff_cnt
   process (clk, rst)
   begin
      if (rst = '1') then
         bit_stuff_cnt <= "001";    
      elsif rising_edge(clk) then
            if (bit_de_stuff_reset = '1') then
               bit_stuff_cnt <= "001" ;    
            else
               if ((sample_point and bit_stuff_cnt_en) = '1') then
                  if (bit_stuff_cnt = "101") then
                     bit_stuff_cnt <= "001" ;    
                  else
                     if (sampled_bit = sampled_bit_q) then
                        bit_stuff_cnt <= bit_stuff_cnt + "001" ;    
                     else
                        bit_stuff_cnt <= "001" ;    
                     end if;
                  end if;
               end if;
         end if;
      end if;
   end process;

   -- bit_stuff_cnt_tx
   process (clk, rst)
   begin
      if (rst = '1') then
         bit_stuff_cnt_tx <= "001";    
      elsif rising_edge(clk) then
            if ((reset_mode = '1') or (bit_de_stuff_reset = '1')) then
               bit_stuff_cnt_tx <= "001" ;    
            else
               if ((tx_point_q and bit_stuff_cnt_en) = '1') then
                  if (bit_stuff_cnt_tx = "101") then
                     bit_stuff_cnt_tx <= "001" ;    
                  else
                     if (tx_xhdl29 = tx_q) then
                        bit_stuff_cnt_tx <= bit_stuff_cnt_tx + "001" ;    
                     else
                        bit_stuff_cnt_tx <= "001" ;    
                     end if;
                  end if;
               end if;
         end if;
      end if;
   end process;
   bit_de_stuff <= CONV_STD_LOGIC(bit_stuff_cnt = "101") ;
   bit_de_stuff_tx <= CONV_STD_LOGIC(bit_stuff_cnt_tx = "101") ;
   stuff_err <= ((sample_point and bit_stuff_cnt_en) and bit_de_stuff) and CONV_STD_LOGIC(sampled_bit = sampled_bit_q) ;

   -- Generating delayed signals
   process (clk, rst)
   begin
      if (rst = '1') then
         reset_mode_q <= '0' ;    
         node_bus_off_q <= '0' ;    
      elsif rising_edge(clk) then
         reset_mode_q <= reset_mode ;    
         node_bus_off_q <= node_bus_off_xhdl13 ;    
      end if;
   end process;

   process (clk, rst)
   begin
      if (rst = '1') then
         crc_enable <= '0';    
      elsif rising_edge(clk) then
         if (rst_crc_enable = '1') then
            crc_enable <= '0' ;    
         else
            if (go_crc_enable = '1') then
               crc_enable <= '1' ;    
            end if;
         end if;
      end if;
   end process;

   -- CRC error generation
   process (clk, rst)
   begin
      if (rst = '1') then
         crc_err <= '0';    
      elsif rising_edge(clk) then
         if ((reset_mode or error_frame_ended) = '1') then
            crc_err <= '0' ;    
         else
            if (go_rx_ack = '1') then
               crc_err <= CONV_STD_LOGIC(crc_in /= calculated_crc) ;    
            end if;
         end if;
      end if;
   end process;
   -- Conditions for form error
   form_err <= sample_point and ((((not bit_de_stuff) and rx_crc_lim) and (not sampled_bit)) or (rx_ack_lim and (not sampled_bit)) or (((CONV_STD_LOGIC(eof_cnt < "110") and rx_eof) and (not sampled_bit)) and (not transmitter_xhdl8)) or (((rx_eof) and (not sampled_bit)) and transmitter_xhdl8)) ;

   process (clk, rst)
   begin
      if (rst = '1') then
         ack_err_latched <= '0';    
      elsif rising_edge(clk) then
         if ((reset_mode or error_frame_ended or go_overload_frame_xhdl32) = '1') then
            ack_err_latched <= '0' ;    
         else
            if (ack_err = '1') then
               ack_err_latched <= '1' ;    
            end if;
         end if;
      end if;
   end process;

   process (clk, rst)
   begin
      if (rst = '1') then
         bit_err_latched <= '0';    
      elsif rising_edge(clk) then
         if ((reset_mode or error_frame_ended or go_overload_frame_xhdl32) = '1') then
            bit_err_latched <= '0' ;    
         else
            if (bit_err = '1') then
               bit_err_latched <= '1' ;    
            end if;
         end if;
      end if;
   end process;
   -- Rule 5 (Fault confinement).
   rule5 <= bit_err and ((((not node_error_passive_xhdl26) and error_frame) and CONV_STD_LOGIC(error_cnt1 < "111")) or (overload_frame_xhdl4 and CONV_STD_LOGIC(overload_cnt1 < "111"))) ;

   -- Rule 3 exception 1 - first part (Fault confinement).
   process (clk, rst)
   begin
      if (rst = '1') then
         rule3_exc1_1 <= '0';    
      elsif rising_edge(clk) then
         if ((error_flag_over or rule3_exc1_2) = '1') then
            rule3_exc1_1 <= '0' ;    
         else
            if (((transmitter_xhdl8 and node_error_passive_xhdl26) and ack_err) = '1') then
               rule3_exc1_1 <= '1' ;    
            end if;
         end if;
      end if;
   end process;

   -- Rule 3 exception 1 - second part (Fault confinement).
   process (clk, rst)
   begin
      if (rst = '1') then
         rule3_exc1_2 <= '0';    
      elsif rising_edge(clk) then
         if ((go_error_frame_xhdl33 or rule3_exc1_2) = '1') then
            rule3_exc1_2 <= '0' ;    
         else
            if ((((rule3_exc1_1 and CONV_STD_LOGIC(error_cnt1 < "111")) and sample_point) and (not sampled_bit)) = '1') then
               rule3_exc1_2 <= '1' ;    
            end if;
         end if;
      end if;
   end process;

   process (clk, rst)
   begin
      if (rst = '1') then
         stuff_err_latched <= '0';    
      elsif rising_edge(clk) then
         if ((reset_mode or error_frame_ended or go_overload_frame_xhdl32) = '1') then
            stuff_err_latched <= '0' ;    
         else
            if (stuff_err = '1') then
               stuff_err_latched <= '1' ;    
            end if;
         end if;
      end if;
   end process;

   process (clk, rst)
   begin
      if (rst = '1') then
         form_err_latched <= '0';    
      elsif rising_edge(clk) then
         if ((reset_mode or error_frame_ended or go_overload_frame_xhdl32) = '1') then
            form_err_latched <= '0' ;    
         else
            if (form_err = '1') then
               form_err_latched <= '1' ;    
            end if;
         end if;
      end if;
   end process;
   
    CrcEnableValid <= ((crc_enable and sample_point) and (not bit_de_stuff));
   
    RxCrc : CanLiteCrc 
        port map (
            clk => clk,
            data => sampled_bit,
            enable => CrcEnableValid,
            initialize => go_crc_enable,
            crc => calculated_crc
        );   
   
    reset_wr_fifo <=
        '1' when (data_cnt = b"0001" and remote_rq = '1') else
        '1' when (data_cnt = (unsigned(RxDlc) + 1) and RxDlc < b"1000") else
        '1' when data_cnt = b"1001" else
        reset_mode;
   err <= form_err or stuff_err or bit_err or ack_err or form_err_latched or stuff_err_latched or bit_err_latched or ack_err_latched or crc_err ;

   -- Data counter. Length of the data is limited to 8 bytes.
   process (clk, rst)
   begin
      if (rst = '1') then
         data_cnt <= (others => '0');
      elsif rising_edge(clk) then
         if (reset_wr_fifo = '1') then
            data_cnt <= (others => '0');
         else
            if (wr_fifo = '1') then
               data_cnt <= data_cnt + 1;
            end if;
         end if;
      end if;
   end process;

   -- Transmitting error frame.
   process (clk, rst)
   begin
      if (rst = '1') then
         error_frame <= '0';    
      elsif rising_edge(clk) then
         if ((set_reset_mode_xhdl12 or error_frame_ended or go_overload_frame_xhdl32) = '1') then
            error_frame <= '0' ;    
         else
            if (go_error_frame_xhdl33 = '1') then
               error_frame <= '1' ;    
            end if;
         end if;
      end if;
   end process;

   process (clk, rst)
   begin
      if (rst = '1') then
         error_cnt1 <= "000";    
      elsif rising_edge(clk) then
         if ((error_frame_ended or go_error_frame_xhdl33 or go_overload_frame_xhdl32) = '1') then
            error_cnt1 <= "000" ;    
         else
            if (((error_frame and tx_point) and CONV_STD_LOGIC(error_cnt1 < "111")) = '1') then
               error_cnt1 <= error_cnt1 + "001" ;    
            end if;
         end if;
      end if;
   end process;
   error_flag_over <= ((((not node_error_passive_xhdl26) and sample_point) and CONV_STD_LOGIC(error_cnt1 = "111")) or ((node_error_passive_xhdl26 and sample_point) and CONV_STD_LOGIC(passive_cnt = "110"))) and (not enable_error_cnt2) ;

   process (clk, rst)
   begin
      if (rst = '1') then
         error_flag_over_latched <= '0';    
      elsif rising_edge(clk) then
         if ((error_frame_ended or go_error_frame_xhdl33 or go_overload_frame_xhdl32) = '1') then
            error_flag_over_latched <= '0' ;    
         else
            if (error_flag_over = '1') then
               error_flag_over_latched <= '1' ;    
            end if;
         end if;
      end if;
   end process;

   process (clk, rst)
   begin
      if (rst = '1') then
         enable_error_cnt2 <= '0';    
      elsif rising_edge(clk) then
         if ((error_frame_ended or go_error_frame_xhdl33 or go_overload_frame_xhdl32) = '1') then
            enable_error_cnt2 <= '0' ;    
         else
            if ((error_frame and (error_flag_over and sampled_bit)) = '1') then
               enable_error_cnt2 <= '1' ;    
            end if;
         end if;
      end if;
   end process;

   process (clk, rst)
   begin
      if (rst = '1') then
         error_cnt2 <= "000";    
      elsif rising_edge(clk) then
         if ((error_frame_ended or go_error_frame_xhdl33 or go_overload_frame_xhdl32) = '1') then
            error_cnt2 <= "000" ;    
         else
            if ((enable_error_cnt2 and tx_point) = '1') then
               error_cnt2 <= error_cnt2 + "001" ;    
            end if;
         end if;
      end if;
   end process;

   process (clk, rst)
   begin
      if (rst = '1') then
         delayed_dominant_cnt <= "000";    
      elsif rising_edge(clk) then
         if ((enable_error_cnt2 or go_error_frame_xhdl33 or enable_overload_cnt2 or go_overload_frame_xhdl32) = '1') then
            delayed_dominant_cnt <= "000" ;    
         else
            if (((sample_point and (not sampled_bit)) and CONV_STD_LOGIC((error_cnt1 = "111") or (overload_cnt1 = "111"))) = '1') then
               delayed_dominant_cnt <= delayed_dominant_cnt + "001" ;    
            end if;
         end if;
      end if;
   end process;

   -- passive_cnt
   process (clk, rst)
   begin
      if (rst = '1') then
         passive_cnt <= "001";    
      elsif rising_edge(clk) then
         if ((error_frame_ended or go_error_frame_xhdl33 or go_overload_frame_xhdl32 or first_compare_bit) = '1') then
            passive_cnt <= "001" ;    
         else
            if ((sample_point and CONV_STD_LOGIC(passive_cnt < "110")) = '1') then
               if (((error_frame and (not enable_error_cnt2)) and CONV_STD_LOGIC(sampled_bit = sampled_bit_q)) = '1') then
                  passive_cnt <= passive_cnt + "001" ;    
               else
                  passive_cnt <= "001" ;    
               end if;
            end if;
         end if;
      end if;
   end process;

   -- When comparing 6 equal bits, first is always equal
   process (clk, rst)
   begin
      if (rst = '1') then
         first_compare_bit <= '0';    
      elsif rising_edge(clk) then
         if (go_error_frame_xhdl33 = '1') then
            first_compare_bit <= '1' ;    
         else
            if (sample_point = '1') then
               first_compare_bit <= '0';    
            end if;
         end if;
      end if;
   end process;

   -- Transmitting overload frame.
   process (clk, rst)
   begin
      if (rst = '1') then
         overload_frame_xhdl4 <= '0';    
      elsif rising_edge(clk) then
         if ((overload_frame_ended or go_error_frame_xhdl33) = '1') then
            overload_frame_xhdl4 <= '0' ;    
         else
            if (go_overload_frame_xhdl32 = '1') then
               overload_frame_xhdl4 <= '1' ;    
            end if;
         end if;
      end if;
   end process;

   process (clk, rst)
   begin
      if (rst = '1') then
         overload_cnt1 <= "000";    
      elsif rising_edge(clk) then
         if ((overload_frame_ended or go_error_frame_xhdl33 or go_overload_frame_xhdl32) = '1') then
            overload_cnt1 <= "000" ;    
         else
            if (((overload_frame_xhdl4 and tx_point) and CONV_STD_LOGIC(overload_cnt1 < "111")) = '1') then
               overload_cnt1 <= overload_cnt1 + "001" ;    
            end if;
         end if;
      end if;
   end process;
   overload_flag_over <= (sample_point and CONV_STD_LOGIC(overload_cnt1 = "111")) and (not enable_overload_cnt2) ;

   process (clk, rst)
   begin
      if (rst = '1') then
         enable_overload_cnt2 <= '0';    
      elsif rising_edge(clk) then
         if ((overload_frame_ended or go_error_frame_xhdl33 or go_overload_frame_xhdl32) = '1') then
            enable_overload_cnt2 <= '0' ;    
         else
            if ((overload_frame_xhdl4 and (overload_flag_over and sampled_bit)) = '1') then
               enable_overload_cnt2 <= '1' ;    
            end if;
         end if;
      end if;
   end process;

   process (clk, rst)
   begin
      if (rst = '1') then
         overload_cnt2 <= "000";    
      elsif rising_edge(clk) then
         if ((overload_frame_ended or go_error_frame_xhdl33 or go_overload_frame_xhdl32) = '1') then
            overload_cnt2 <= "000" ;    
         else
            if ((enable_overload_cnt2 and tx_point) = '1') then
               overload_cnt2 <= overload_cnt2 + "001" ;    
            end if;
         end if;
      end if;
   end process;

   send_ack_xhdl35 <= (((not tx_state_xhdl2) and rx_ack) and (not err));

   process (reset_mode, node_bus_off_xhdl13, tx_state_xhdl2, go_tx_xhdl34, bit_de_stuff_tx, tx_bit, tx_q, send_ack_xhdl35, go_overload_frame_xhdl32, overload_frame_xhdl4, overload_cnt1, go_error_frame_xhdl33, error_frame, error_cnt1, node_error_passive_xhdl26)
      variable tx_next_xhdl30_xhdl105  : std_logic;
   begin
      if ((reset_mode or node_bus_off_xhdl13) = '1') then
         -- Reset or node_bus_off
         
         tx_next_xhdl30_xhdl105 := '1';    
      else
         if ((go_error_frame_xhdl33 or error_frame) = '1') then
            -- Transmitting error frame
            
            if (error_cnt1 < "110") then
               if (node_error_passive_xhdl26 = '1') then
                  tx_next_xhdl30_xhdl105 := '1';    
               else
                  tx_next_xhdl30_xhdl105 := '0';    
               end if;
            else
               tx_next_xhdl30_xhdl105 := '1';    
            end if;
         else
            if ((go_overload_frame_xhdl32 or overload_frame_xhdl4) = '1') then
               -- Transmitting overload frame
               
               if (overload_cnt1 < "110") then
                  tx_next_xhdl30_xhdl105 := '0';    
               else
                  tx_next_xhdl30_xhdl105 := '1';    
               end if;
            else
               if ((go_tx_xhdl34 or tx_state_xhdl2) = '1') then
                  -- Transmitting message
                  
                  tx_next_xhdl30_xhdl105 := ((not bit_de_stuff_tx) and tx_bit) or (bit_de_stuff_tx and (not tx_q));    
               else
                  if (send_ack_xhdl35 = '1') then
                     -- Acknowledge
                     
                     tx_next_xhdl30_xhdl105 := '0';    
                  else
                     tx_next_xhdl30_xhdl105 := '1';    
                  end if;
               end if;
            end if;
         end if;
      end if;
      tx_next_xhdl30 <= tx_next_xhdl30_xhdl105;
   end process;

   process (clk, rst)
   begin
      if (rst = '1') then
         tx_xhdl29 <= '1';    
      elsif rising_edge(clk) then
         if (reset_mode = '1') then
            tx_xhdl29 <= '1';    
         else
            if (tx_point = '1') then
               tx_xhdl29 <= tx_next_xhdl30 ;    
            end if;
         end if;
      end if;
   end process;

   process (clk, rst)
   begin
      if (rst = '1') then
         tx_q <= '0' ;    
      elsif rising_edge(clk) then
         if (reset_mode = '1') then
            tx_q <= '0' ;    
         else
            if (tx_point = '1') then
               tx_q <= tx_xhdl29 and (not go_early_tx_latched) ;    
            end if;
         end if;
      end if;
   end process;

   -- Delayed tx point 
   process (clk, rst)
   begin
      if (rst = '1') then
         tx_point_q <= '0' ;    
      elsif rising_edge(clk) then
         if (reset_mode = '1') then
            tx_point_q <= '0' ;    
         else
            tx_point_q <= tx_point ;    
         end if;
      end if;
   end process;   
   
   BasicChainReversed <= '0' & TxFrame.Id & TxFrame.Rtr & b"00" & TxFrame.Dlc;
   BasicChainDataReversed <=
       TxFrame.Data(0) &
       TxFrame.Data(1) &
       TxFrame.Data(2) &
       TxFrame.Data(3) &
       TxFrame.Data(4) &
       TxFrame.Data(5) &
       TxFrame.Data(6) &
       TxFrame.Data(7);
    basic_chain <= Reverse(BasicChainReversed);
    basic_chain_data <= Reverse(BasicChainDataReversed);
        
    process (rx_data, tx_pointer, rx_crc, calculated_crc, basic_chain_data, basic_chain, finish_msg)
    begin       
        if (rx_data = '1') then -- data stage
            tx_bit <= basic_chain_data(to_integer(tx_pointer));
        else
            if (rx_crc = '1') then
                if tx_pointer(3 downto 0) = x"F" then
                    tx_bit <= '0';
                else
                    tx_bit <= calculated_crc(to_integer(14 - tx_pointer(3 downto 0)));
                end if;
            else
               if (finish_msg = '1') then
                  tx_bit <= '1';
               else
                  tx_bit <= basic_chain(to_integer(tx_pointer));
               end if;
            end if;
        end if;
    end process;

   limited_tx_cnt_std <= b"111111" when TxFrame.Dlc(3) = '1' else (unsigned(TxFrame.Dlc(2 downto 0)) & b"000") - 1;
   rst_tx_pointer <= (((((not bit_de_stuff_tx) and tx_point) and (not rx_data))) and CONV_STD_LOGIC(tx_pointer = b"010010")) or (((((not bit_de_stuff_tx) and tx_point) and rx_data)) and CONV_STD_LOGIC(tx_pointer = limited_tx_cnt_std)) or (tx_point and rx_crc_lim) or (go_rx_idle) or (reset_mode) or (overload_frame_xhdl4) or (error_frame) ;

   process (clk, rst)
   begin
      if (rst = '1') then
         tx_pointer <= (others => '0');
      elsif rising_edge(clk) then
         if (rst_tx_pointer = '1') then
            tx_pointer <= (others => '0');
         else
            if ((go_early_tx or ((tx_point and (tx_state_xhdl2 or go_tx_xhdl34)) and (not bit_de_stuff_tx))) = '1') then
               tx_pointer <= tx_pointer + 1;
            end if;
         end if;
      end if;
   end process;
   tx_successful_xhdl19 <= ((((transmitter_xhdl8 and go_rx_inter_xhdl9) and (not go_error_frame_xhdl33)) and (not error_frame_ended)) and (not overload_frame_ended)) and (not arbitration_lost) ;

   process (clk, rst)
   begin
      if (rst = '1') then
         need_to_tx_xhdl20 <= '0';    
      elsif rising_edge(clk) then
         if ((tx_successful_xhdl19 or reset_mode) = '1') then
            need_to_tx_xhdl20 <= '0' ;
         else
            if ((tx_request and sample_point) = '1') then
               need_to_tx_xhdl20 <= '1' ;    
            end if;
         end if;
      end if;
   end process;
   go_early_tx <= ((((need_to_tx_xhdl20 and (not tx_state_xhdl2)) and (not suspend or CONV_STD_LOGIC(susp_cnt = "111"))) and sample_point) and (not sampled_bit)) and (rx_idle_xhdl6 or last_bit_of_inter) ;
   go_tx_xhdl34 <= ((need_to_tx_xhdl20 and (not tx_state_xhdl2)) and (not suspend or (sample_point and CONV_STD_LOGIC(susp_cnt = "111")))) and (go_early_tx or rx_idle_xhdl6) ;

   -- go_early_tx latched (for proper bit_de_stuff generation)
   process (clk, rst)
   begin
      if (rst = '1') then
         go_early_tx_latched <= '0';    
      elsif rising_edge(clk) then
         if ((reset_mode or tx_point) = '1') then
            go_early_tx_latched <= '0' ;    
         else
            if (go_early_tx = '1') then
               go_early_tx_latched <= '1' ;    
            end if;
         end if;
      end if;
   end process;

   -- Tx state
   process (clk, rst)
   begin
      if (rst = '1') then
         tx_state_xhdl2 <= '0';    
      elsif rising_edge(clk) then
         if ((reset_mode or go_rx_inter_xhdl9 or error_frame or arbitration_lost) = '1') then
            tx_state_xhdl2 <= '0' ;    
         else
            if (go_tx_xhdl34 = '1') then
               tx_state_xhdl2 <= '1' ;    
            end if;
         end if;
      end if;
   end process;

   process (clk, rst)
   begin
      if (rst = '1') then
         tx_state_q_xhdl3 <= '0' ;    
      elsif rising_edge(clk) then
         if (reset_mode = '1') then
            tx_state_q_xhdl3 <= '0' ;    
         else
            tx_state_q_xhdl3 <= tx_state_xhdl2 ;    
         end if;
      end if;
   end process;

   -- Node is a transmitter
   process (clk, rst)
   begin
      if (rst = '1') then
         transmitter_xhdl8 <= '0';    
      elsif rising_edge(clk) then
         if (go_tx_xhdl34 = '1') then
            transmitter_xhdl8 <= '1' ;    
         else
            if ((reset_mode or go_rx_idle or (suspend and go_rx_id1)) = '1') then
               transmitter_xhdl8 <= '0' ;    
            end if;
         end if;
      end if;
   end process;

   -- Signal "transmitting" signals that the core is a transmitting (message, error frame or overload frame). No synchronization is done meanwhile.
   -- Node might be both transmitter or receiver (sending error or overload frame)
   process (clk, rst)
   begin
      if (rst = '1') then
         transmitting_q <= '0';    
      elsif rising_edge(clk) then
         if ((go_error_frame_xhdl33 or go_overload_frame_xhdl32 or go_tx_xhdl34 or send_ack_xhdl35) = '1') then
            transmitting_q <= '1' ;    
         else
            if ((reset_mode or go_rx_idle or (go_rx_id1 and (not tx_state_xhdl2)) or (arbitration_lost and tx_state_xhdl2)) = '1') then
               transmitting_q <= '0' ;    
            end if;
         end if;
      end if;
   end process;

   process (clk, rst)
   begin
      if (rst = '1') then
         suspend <= '0';    
      elsif rising_edge(clk) then
         if ((reset_mode or (sample_point and CONV_STD_LOGIC(susp_cnt = "111"))) = '1') then
            suspend <= '0' ;    
         else
            if (((not_first_bit_of_inter_xhdl10 and transmitter_xhdl8) and node_error_passive_xhdl26) = '1') then
               suspend <= '1' ;    
            end if;
         end if;
      end if;
   end process;

   process (clk, rst)
   begin
      if (rst = '1') then
         susp_cnt_en <= '0';    
      elsif rising_edge(clk) then
         if ((reset_mode or (sample_point and CONV_STD_LOGIC(susp_cnt = "111"))) = '1') then
            susp_cnt_en <= '0' ;    
         else
            if (((suspend and sample_point) and last_bit_of_inter) = '1') then
               susp_cnt_en <= '1' ;    
            end if;
         end if;
      end if;
   end process;

   process (clk, rst)
   begin
      if (rst = '1') then
         susp_cnt <= "000";    
      elsif rising_edge(clk) then
         if ((reset_mode or (sample_point and CONV_STD_LOGIC(susp_cnt = "111"))) = '1') then
            susp_cnt <= "000" ;    
         else
            if ((susp_cnt_en and sample_point) = '1') then
               susp_cnt <= susp_cnt + "001" ;    
            end if;
         end if;
      end if;
   end process;

   process (clk, rst)
   begin
      if (rst = '1') then
         finish_msg <= '0';    
      elsif rising_edge(clk) then
         if ((go_rx_idle or go_rx_id1 or error_frame or reset_mode) = '1') then
            finish_msg <= '0' ;    
         else
            if (go_rx_crc_lim = '1') then
               finish_msg <= '1' ;    
            end if;
         end if;
      end if;
   end process;

   process (clk, rst)
   begin
      if (rst = '1') then
         arbitration_lost <= '0';    
      elsif rising_edge(clk) then
         if ((go_rx_idle or error_frame_ended) = '1') then
            arbitration_lost <= '0' ;    
         else
            if (((((transmitter_xhdl8 and sample_point) and tx_xhdl29) and arbitration_field) and not sampled_bit) = '1') then
               arbitration_lost <= '1' ;    
            end if;
         end if;
      end if;
   end process;

   process (clk, rst)
   begin
     if (rst = '1') then
       arbitration_field_d <= '0';
     elsif rising_edge(clk) then
         if (sample_point = '1') then
             arbitration_field_d <= arbitration_field;
         end if;
     end if;
   end process;
     
   process (clk, rst)
   begin
      if (rst = '1') then
         arbitration_cnt <= (others =>'0');    
      elsif rising_edge(clk) then
          if ((sample_point = '1') and (bit_de_stuff = '0')) then
            if (arbitration_field_d = '1') then
               arbitration_cnt <= arbitration_cnt + "01";    
            else 
               arbitration_cnt <= (others =>'0');    
            end if;
          end if;
      end if;
   end process;

   process (clk, rst)
   begin
      if (rst = '1') then
         rx_err_cnt_xhdl15 <= (others => '0');
      elsif rising_edge(clk) then
        if (set_reset_mode_xhdl12 = '1') then
           rx_err_cnt_xhdl15 <= (others => '0');
        else
           if ((not transmitter_xhdl8 or arbitration_lost) = '1') then
              if ((((go_rx_ack_lim and (not go_error_frame_xhdl33)) and (not crc_err)) and CONV_STD_LOGIC(rx_err_cnt_xhdl15 > 0)) = '1') then
                 if (rx_err_cnt_xhdl15 > 127) then
                    rx_err_cnt_xhdl15 <= to_unsigned(127, rx_err_cnt_xhdl15'length);
                 else
                    rx_err_cnt_xhdl15 <= rx_err_cnt_xhdl15 - 1;    
                 end if;
              else
                 if (rx_err_cnt_xhdl15 < 128) then
                    if ((go_error_frame_xhdl33 and (not rule5)) = '1') then
                       rx_err_cnt_xhdl15 <= rx_err_cnt_xhdl15 + 1;    
                    else
                       if ((((((error_flag_over and (not error_flag_over_latched)) and sample_point) and (not sampled_bit)) and CONV_STD_LOGIC(error_cnt1 = 7)) or (go_error_frame_xhdl33 and rule5) or ((sample_point and (not sampled_bit)) and CONV_STD_LOGIC(delayed_dominant_cnt = 7))) = '1') then
                          rx_err_cnt_xhdl15 <= rx_err_cnt_xhdl15 + 8;    
                       end if;
                    end if;
                 end if;
              end if;
           end if;
        end if;
     end if;
   end process;

   process (clk, rst)
   begin
      if (rst = '1') then
         tx_err_cnt_xhdl16 <= (others => '0');
      elsif rising_edge(clk) then
        if (set_reset_mode_xhdl12 = '1') then
           tx_err_cnt_xhdl16 <= to_unsigned(128, tx_err_cnt_xhdl16'length);
        else
           if ((CONV_STD_LOGIC(tx_err_cnt_xhdl16 > 0) and (tx_successful_xhdl19 or bus_free)) = '1') then
              tx_err_cnt_xhdl16 <= tx_err_cnt_xhdl16 - 1;    
           else
              if ((transmitter_xhdl8 and (not arbitration_lost)) = '1') then
                 if ((((sample_point and (not sampled_bit)) and CONV_STD_LOGIC(delayed_dominant_cnt = 7)) or (go_error_frame_xhdl33 and rule5) or ((go_error_frame_xhdl33 and (not ((transmitter_xhdl8 and node_error_passive_xhdl26) and ack_err))) and (not (((((transmitter_xhdl8 and stuff_err) and arbitration_field) and sample_point) and tx_xhdl29) and (not sampled_bit)))) or (error_frame and rule3_exc1_2)) = '1') then
                    tx_err_cnt_xhdl16 <= tx_err_cnt_xhdl16 + 8;
                 end if;
              end if;
           end if;
        end if;
     end if;
   end process;

   process (clk, rst)
   begin
      if (rst = '1') then
         node_error_passive_xhdl26 <= '0';    
      elsif rising_edge(clk) then
         if ((rx_err_cnt_xhdl15 < b"010000000") and (tx_err_cnt_xhdl16 < b"010000000")) then
            node_error_passive_xhdl26 <= '0' ;    
         else
            if (((CONV_STD_LOGIC((rx_err_cnt_xhdl15 >= b"010000000") or (tx_err_cnt_xhdl16 >= b"010000000")) and (error_frame_ended or go_error_frame_xhdl33 or ((not reset_mode) and reset_mode_q))) and (not node_bus_off_xhdl13)) = '1') then
               node_error_passive_xhdl26 <= '1' ;    
            end if;
         end if;
      end if;
   end process;

   process (clk, rst)
   begin
      if (rst = '1') then
         node_bus_off_xhdl13 <= '0';    
      elsif rising_edge(clk) then
         if (((CONV_STD_LOGIC((rx_err_cnt_xhdl15 = b"000000000") and (tx_err_cnt_xhdl16 = b"000000000")) and (not reset_mode))) = '1') then
            node_bus_off_xhdl13 <= '0' ;    
         else
            if (CONV_STD_LOGIC(tx_err_cnt_xhdl16 >= b"100000000") = '1') then
               node_bus_off_xhdl13 <= '1' ;    
            end if;
         end if;
      end if;
   end process;

   process (clk, rst)
   begin
      if (rst = '1') then
         bus_free_cnt <= "0000";    
      elsif rising_edge(clk) then
            if (sample_point = '1') then
               if (((sampled_bit and bus_free_cnt_en) and CONV_STD_LOGIC(bus_free_cnt < "1010")) = '1') then
                  bus_free_cnt <= bus_free_cnt + "0001" ;    
               else
                  bus_free_cnt <= "0000" ;    
               end if;
         end if;
      end if;
   end process;

   process (clk, rst)
   begin
      if (rst = '1') then
         bus_free_cnt_en <= '0';    
      elsif rising_edge(clk) then
         if ((((not reset_mode) and reset_mode_q) or (node_bus_off_q and (not reset_mode))) = '1') then
            bus_free_cnt_en <= '1' ;    
         else
            if ((((sample_point and sampled_bit) and CONV_STD_LOGIC(bus_free_cnt = "1010")) and (not node_bus_off_xhdl13)) = '1') then
               bus_free_cnt_en <= '0' ;    
            end if;
         end if;
      end if;
   end process;

   process (clk, rst)
   begin
      if (rst = '1') then
         bus_free <= '0';    
      elsif rising_edge(clk) then
            if (((sample_point and sampled_bit) and CONV_STD_LOGIC(bus_free_cnt = "1010") and waiting_for_bus_free) = '1') then
               bus_free <= '1' ;    
            else
               bus_free <= '0' ;    
            end if;
      end if;
   end process;

   process (clk, rst)
   begin
      if (rst = '1') then
         waiting_for_bus_free <= '1';    
      elsif rising_edge(clk) then
            if ((bus_free and (not node_bus_off_xhdl13)) = '1') then
               waiting_for_bus_free <= '0' ;    
            elsif ((node_bus_off_q and (not reset_mode)) = '1') then
                  waiting_for_bus_free <= '1' ;    
            end if;
      end if;
   end process;
   set_reset_mode_xhdl12 <= node_bus_off_xhdl13 and (not node_bus_off_q) ;

end architecture Behavioral;