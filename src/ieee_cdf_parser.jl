using DataFrames;
using Match;

"""
    parse_ieee_cdf(filename)

Parses the file (filename) and returns:

auxiliary information:
 - number of lines read (-1 if error),

and the following content DataFrames:
 - bus data frame
 - branch data frame
 - loss zones data frame
 - interchange data frame
 - tie lines data frame

*Sample source files:* https://www2.ee.washington.edu/research/pstca/pf118/pg_tca118bus.htm

*Short format description:* https://www2.ee.washington.edu/research/pstca/formats/cdf.txt

*Full format description:* W. Group, "Common Format For Exchange of Solved Load Flow Data," in IEEE Transactions on Power Apparatus and Systems, vol. PAS-92, no. 6, pp. 1916-1925, Nov. 1973.
doi: 10.1109/TPAS.1973.293571
URL: http://ieeexplore.ieee.org/stamp/stamp.jsp?tp=&arnumber=4075293&isnumber=4075277

REQUIRES PACKAGES:
    - Match
    - DataFrames

"""
function parse_ieee_cdf(fileName::String)
    totalTime, totalLines = open(fileName) do f
        lineCounter = 0;
        readingMode = "INIT"; ## Possible values: INIT, HEADER, BUS, BRANCH, LOSS, INTERCHANGE, TIE

        # TODO: implement checks?
        # - special characters
        # - 
        for line in eachline(f)
            # determine the mode
            # INIT
            # BUS
            # BRANCH
            # LOSS
            # INTERCHANGE
            # END (-999)
            # parse according to the mode
            
            
            
        end
        (lineCounter)
    end
    

end
