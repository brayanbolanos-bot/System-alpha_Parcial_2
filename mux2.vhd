library IEEE ;
use IEEE.std_logic_1164.ALL;

entity mux2 is
	


	port
	(
		-- Input ports
		X	: in  std_logic_vector(3 downto 0);
		Y	: in  std_logic_vector(3 downto 0);
		S : in std_logic;
		

		

		-- Output ports
		m	: out std_logic_vector(3 downto 0)
	);
end mux2;




-- Library Clause(s) (optional)
-- Use Clause(s) (optional)

architecture arch_mux2 of mux2 is

begin
   
	
	m(0)<= (NOT(S)AND X(0)) OR (S AND Y(0));
	m(1)<= (NOT(S)AND X(1)) OR (S AND Y(1));
	m(2)<= (NOT(S)AND X(2)) OR (S AND Y(2));
	m(3)<= (NOT(S)AND X(3)) OR (S AND Y(3));

	-- Process Statement (optional)

	-- Concurrent Procedure Call (optional)

	-- Concurrent Signal Assignment (optional)

	-- Conditional Signal Assignment (optional)

	-- Selected Signal Assignment (optional)

	-- Component Instantiation Statement (optional)

	-- Generate Statement (optional)

end arch_mux2;