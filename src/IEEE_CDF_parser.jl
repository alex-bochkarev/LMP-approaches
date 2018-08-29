module IEEE_CDF_parser

using DataFrames;


"""
Data type to store IEEE CDF data
"""
struct IEEE_CDF
    bus::DataFrame
    branch::DataFrame
    loss::DataFrame
    interchange::DataFrame
    tie::DataFrame
end

"""
Constant definitions
"""
## Bus types
const Bus_PQ_LOAD = 0 # - Unregulated (load, PQ)
const Bus_PQ_GEN  = 1 # - Hold MVAR generation within voltage limits, (PQ)
const Bus_PV_GEN  = 2 # - Hold voltage within VAR limits (gen, PV)
const Bus_SWING   = 3 # - Hold voltage and angle (swing, V-Theta) (must always have one)

# Branch types
const Branch_TL      = 0 # - Transmission line
const Branch_FT      = 1 # - Fixed tap
const Branch_VT_VC   = 2 # - Variable tap for voltage control (TCUL, LTC)
const Branch_VT_MVAR = 3 # - Variable tap (turns ratio) for MVAR control
const Branch_PhS     = 4 # - Variable phase angle for MW control (phase shifter)

"""
    msgWrongFormat(lineNumber, msg)
"""
function msgWrongFormat(lineNumber, msg)
    warn("Error in the input file: line ",lineNumber," --",msg)
    warn("Please check your file. If necessary, consult with the format description in “Common Format For Exchange of Solved Load Flow Data”, IEEE Transactions on Power Apparatus and Systems, vol. PAS-92, no. 6, pp. 1916–1925, Nov. 1973.")
end

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
    - DataFrames

"""
function parse_cdf(fileName::String)
    println("Working with file:",fileName)
    open(fileName) do f
        lineCounter = 1;
        readingMode = "TITLE"; ## Possible values: INIT, TITLE, BUS, BRANCH, LOSS, INTERCHANGE, TIE

        # TODO: implement checks?
        # - special characters
        # + number of items

        # describe necessary data frames
        bus = DataFrame(BusNumber = Int[],
                            Name = String[],
                            LFA = String[], # Load flow area number, non-zero (Int in specs, but string in some of the source files)
                            LZ = Int[], # Loss zone number
                            BusType = Int[], # see constants
                            V = Float16[], # final voltage, p.u.
                            theta = Float16[], # final angle, degrees
                            P_D = Float32[], # load MW
                            Q_D = Float32[], # load MVAR
                            P_G = Float32[], # generation MW
                            Q_G = Float32[], # generation MVAR
                            BaseKV = Float32[],
                            DesV = Float16[], # desired volts, p.u.
                            MaxLimit = Float32[], # Maximum MVAR or voltage limit
                            MinLimit = Float32[], # Minimum --/--/--
                            G = Float32[], # shunt conductance G, p.u.
                            B = Float32[], # shunt susceptance B, p.u.
                            RCBN = Int[] # remote controlled bus number
                            )

        branch = DataFrame(TapBusNo = Int[], # Tap bus number
                           ZBusNo = Int[], # Z bus number
                           LFA = String[], # Load Flow area number, non-zero
                           LZ = Int[], # Loss zone
                           Circuit = Int[], # use 1 for single lines
                           BranchType = Int[], # see constants
                           R = Float32[], # resistance, p.u.
                           X = Float32[], # reactance, p.u.
                           B = Float32[], # line charging B, p.u.
                           MVA_ra1 = Int[],
                           MVA_ra2 = Int[], # line MVA ratings
                           MVA_ra3 = Int[],
                           Control_bus = Int[], # control bus number
                           Side = Int[],
                           TFTR = Float32[], # transformer final turns ratio
                           TFtheta = Float32[], # transformer (phase shifter) final angle
                           MinTap = Float32[], # minimum tap or phase shift
                           MaxTap = Float32[], # maximum tap or phase shift
                           StepSize = Float32[],
                           MinVal = Float32[], # minimum voltage, MVAR or MW limit
                           MaxVal = Float32[], # maximum voltage, MVAR or MW limit

        )

        noItems = 0
        noItems_exp = 0

        for line in eachline(f)
            println("Line ",lineCounter,", mode=",readingMode)
            ## ignoring empty lines
            line=="" ? continue : nothing;
            if readingMode == "TITLE"
                Date = line[2:9]
                SenderID = line[11:30]
                MVAbase = line[32:37]
                Year = line[39:42]
                Season = line[44] ## S = Summer, W = Winter
                CaseID = line[46:end]
                readingMode = "INIT"

            elseif readingMode == "INIT"
                ## INIT mode
                ## expecting section name or end of data
                noItems_exp = 0
                noItems = 0

                m = match(r"(BUS|BRANCH|LOSS\sZONES|INTERCHANGE|TIE\sLINES) DATA FOLLOWS",line)
                if m==nothing
                    # not a valid section start
                    if line=="END OF DATA"
                        ## all the data is parsed
                        break;
                    end
                else
                    # try to extract number of items
                    readingMode = m.captures[1]; # save section type
                    m = match(r"([0-9].+)\sITEMS",line)
                    if m!=nothing
                        noItems_exp = parse(Int64, m.captures[1])
                    else
                        noItems_exp=-1
                        warn("Warning: no number of items specified for the following section --",readingMode)
                    end
                end
            elseif readingMode == "BUS"
                ## BUS mode -- reading bus data
                BusNumber = parse(Int, line[1:4])
                if BusNumber < 0
                    # end of the bus section encountered
                    noItems != noItems_exp ? warn("Warning: no. of items does not coincide with the ITEMS statement in the section head (",readingMode,") -- ",noItems_exp," expected, ",noItems," collected") : nothing
                    readingMode="INIT"
                    continue
                end

                try
                    Name = line[6:17]
                    LFA = line[19:20] # Load flow area number, non-zero
                    LZ = parse(Int,line[21:23]) # Loss zone number
                    BusType = parse(Int, line[25:26]) # see constants
                    V = parse(Float16, line[28:33]) # final voltage, p.u.
                    theta = parse(Float16,line[34:40]) # final angle, degrees
                    P_D = parse(Float32, line[41:49]) # load MW
                    Q_D = parse(Float32, line[50:59]) # load MVAR
                    P_G = parse(Float32, line[60:67]) # generation MW
                    Q_G=parse(Float32,line[68:75]) # generation MVAR
                    println("debug")
                    BaseKV=parse(Float32,line[77:83])
                    DesV=parse(Float16,line[85:90]) # desired volts, p.u.
                    MaxLimit=parse(Float32,line[91:98]) # Maximum MVAR or voltage limit
                    MinLimit=parse(Float32,line[99:106]) # Minimum --/--/--
                    G=parse(Float32,line[107:114]) # shunt conductance G, p.u.
                    B=parse(Float32,line[115:122]) # shunt susceptance B, p.u.
                    RCBN=parse(Int,line[124:end]) # remote controlled bus number

                    if BusType<0 | BusType>3
                        msgWrongFormat(lineCounter, "wrong bus type: ",BusType," -- 0,1,2 or 3 expected")
                        return nothing;
                    end
                    # save the line
                    bus = vcat(bus,DataFrame(BusNumber = BusNumber,
                                             Name = Name,
                                             LFA = LFA,
                                             LZ = LZ,
                                             BusType = BusType,
                                             V = V,
                                             theta = theta,
                                             P_D = P_D,
                                             Q_D = Q_D,
                                             P_G = P_G,
                                             Q_G = Q_G,
                                             BaseKV = BaseKV,
                                             DesV = DesV,
                                             MaxLimit = MaxLimit,
                                             MinLimit = MinLimit,
                                             G = G,
                                             B = B,
                                             RCBN = RCBN))
                    noItems+=1
                catch
                    msgWrongFormat(lineCounter+1,"line parsing error")
                    return nothing
                end

            elseif readingMode == "BRANCH"
                ## BRANCH mode -- reading branch data
                TapBusNo = parse(Int, line[1:4])
                if TapBusNo < 0
                    # end of the section encountered
                    noItems != noItems_exp ? warn("Warning: no. of items does not coincide with the ITEMS statement in the section head (",readingMode,") -- ",noItems_exp," expected, ",noItems," collected") : nothing
                    readingMode="INIT"
                    continue
                end

               # try
                    branch = vcat(branch, DataFrame(
                                  TapBusNo = TapBusNo,  # Tap bus number (I) *
                                  ZBusNo = parse(Int,line[6:9]),  # Z bus number (I) *
                                  LFA = line[11:12],  # Load flow area (I)
                                  LZ = parse(Int,line[13:15]),  # Loss zone (I)
                                  Circuit = parse(Int,line[17]),  # Circuit (I) * (Use 1 for single lines)
                                  BranchType = parse(Int,line[19]),  # Type (I) *
                                  R = parse(Float32,line[20:29]),  # Branch resistance R, per unit (F) *
                                  X = parse(Float32,line[30:40]),  # Branch reactance X, per unit (F) * No zero impedance lines
                                  B = parse(Float32,line[41:50]),  # Line charging B, per unit (F) * (total line charging, +B)
                                  MVA_ra1 = parse(Int,line[51:55]),  # Line MVA rating No 1 (I) Left justify!
                                  MVA_ra2 = parse(Int,line[57:61]),  # Line MVA rating No 2 (I) Left justify!
                                  MVA_ra3 = parse(Int,line[63:67]),  # Line MVA rating No 3 (I) Left justify!
                                  Control_bus = parse(Int,line[69:72]),  # Control bus number
                                  Side = parse(Int,line[74]),  # Side (I)
                                  TFTR = parse(Float32,line[77:82]),  # Transformer final turns ratio (F)
                                  TFtheta = parse(Float32,line[84:90]),  # Transformer (phase shifter) final angle (F)
                                  MinTap = parse(Float32,line[91:97]),  # Minimum tap or phase shift (F)
                                  MaxTap = parse(Float32,line[98:104]),  # Maximum tap or phase shift (F)
                                  StepSize = parse(Float32,line[106:111]),  # Step size (F)
                                  MinVal = parse(Float32,line[113:119]),  # Minimum voltage, MVAR or MW limit (F)
                                  MaxVal = parse(Float32,line[120:end])  # Maximum voltage, MVAR or MW limit (F)
                                  ))

                    ## TODO: implement checks for constants (BusType, smth else)
                    noItems+=1
                #catch
                 #   msgWrongFormat(lineCounter+1,"line parsing error")
                  #  return nothing
                #end
            end

            lineCounter+=1
        end

(lineCounter,bus,branch) # return value

end # function

end # do
end # module
