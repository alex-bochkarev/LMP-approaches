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
                       MaxVal = Float32[] # maximum voltage, MVAR or MW limit
                       )
    
    loss_zones = DataFrame(LZ = Int[],
                           LZName = String[])
    
    interchange = DataFrame(AreaNum = Int[], # Area number (I) no zeros! *
                            ISB = Int[], # Interchange slack bus number (I) *
                            ASB = String[], # Alternate swing bus name (A)
                            AIexport = Float32[], # Area interchange export, MW (F) (+ = out) *
                            AItol = Float32[], # Area interchange tolerance, MW (F) *
                            ACode = String[], # Area code (abbreviated name) (A) *
                            AName = String[] # Area name (A)
                            )

  tie = DataFrame(MBusNum = Int[], # Metered bus number (I)
                  MAreaNum = Int[], # Metered area number (I)
                  NMBusNum = Int[], # Non-metered bus number (I)
                  NMAreaNum = Int[], # Non-metered area number (I)
                  CircuitNum = Int[] # Circuit number
                  )


    open(fileName) do f
        lineCounter = 1;
        readingMode = "TITLE"; 

        # TODO: implement checks?
        # - special characters
        # + number of items

        # describe necessary data frames
        noItems = 0
        noItems_exp = 0

        for line in eachline(f)
            line=="" ? continue : nothing;             ## ignoring empty lines

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
                    m = match(r"(BUS\sDATA|BRANCH\sDATA|LOSS\sZONES|INTERCHANGE\sDATA|TIE\sLINES)\s+FOLLOWS",line)
                    if m==nothing
                        # not a valid section start
                        if line=="END OF DATA"
                            ## all the data is parsed
                            break;
                        end
                    else
                        # try to extract number of items
                        readingMode = m.captures[1]; # save section type
                        m = match(r"([0-9]+)\s+ITEMS",line)
                        if m!=nothing
                            noItems_exp = parse(Int64, m.captures[1])
                        else
                            noItems_exp=-1
                            warn("Warning: no number of items specified for the following section: `",readingMode)
                        end
                    end
            else
                EntryIndex = parse(Int, line[1:min(4,length(line))])
                if EntryIndex < 0
                    # end of the section encountered
                    noItems != noItems_exp ? warn("Warning: no. of items does not coincide with the ITEMS statement in the section head (",readingMode,") -- ",noItems_exp," expected, ",noItems," collected") : nothing
                    readingMode="INIT"
                    lineCounter+=1
                    continue
                end
                
                if readingMode == "BUS DATA"
                    ## BUS mode -- reading bus data
                    
                    try
                        bus = vcat(bus, DataFrame(BusNumber = EntryIndex,
                                                  Name = line[6:17],
                                                  LFA = line[19:20], # Load flow area number, non-zero
                                                  LZ = parse(Int,line[21:23]), # Loss zone number
                                                  BusType = parse(Int, line[25:26]), # see constants
                                                  V = parse(Float16, line[28:33]), # final voltage, p.u.
                                                  theta = parse(Float16,line[34:40]), # final angle, degrees
                                                  P_D = parse(Float32, line[41:49]), # load MW
                                                  Q_D = parse(Float32, line[50:59]), # load MVAR
                                                  P_G = parse(Float32, line[60:67]), # generation MW
                                                  Q_G=parse(Float32,line[68:75]), # generation MVAR
                                                  BaseKV=parse(Float32,line[77:83]),
                                                  DesV=parse(Float16,line[85:90]), # desired volts, p.u.
                                                  MaxLimit=parse(Float32,line[91:98]), # Maximum MVAR or voltage limit
                                                  MinLimit=parse(Float32,line[99:106]), # Minimum --/--/--
                                                  G=parse(Float32,line[107:114]), # shunt conductance G, p.u.
                                                  B=parse(Float32,line[115:122]), # shunt susceptance B, p.u.
                                                  RCBN=parse(Int,line[124:end]), # remote controlled bus number
                                                  ))
                        
                        if bus[end,:BusType]<0 | bus[end,:BusType]>3
                            msgWrongFormat(lineCounter, "wrong bus type: ",BusType," -- 0,1,2 or 3 expected")
                            return nothing;
                        end
                        
                        noItems+=1
                    catch
                        msgWrongFormat(lineCounter,"line parsing error")
                        return nothing
                    end

                elseif readingMode == "BRANCH DATA"
                    ## BRANCH mode -- reading branch data
                    try
                        branch = vcat(branch, DataFrame(
                            TapBusNo = EntryIndex,  # Tap bus number (I) *
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

                    catch
                        msgWrongFormat(lineCounter,"line parsing error")
                    #    return nothing
                    end
elseif readingMode == "LOSS ZONES"
# loss zones mode
try
    loss_zones = vcat(loss_zones, DataFrame(
        LZ = EntryIndex,
        LZName = line[5:end]))
    
    ## TODO: implement checks for constants (BusType, smth else)
    noItems+=1
catch
    msgWrongFormat(lineCounter,"line parsing error")
    return nothing
end

elseif readingMode == "INTERCHANGE DATA"

try
    interchange = vcat(interchange, DataFrame(
        AreaNum = EntryIndex,
        ISB = parse(Int,line[4:7]),  # Interchange slack bus number (I) *
        ASB = line[9:20],  # Alternate swing bus name (A)
        AIexport = parse(Float32,line[21:28]),  # Area interchange export, MW (F) (+ = out) *
        AItol = parse(Float32,line[30:35]),  # Area interchange tolerance, MW (F) *
        ACode = line[38:43],  # Area code (abbreviated name) (A) *
        AName = line[46:end]  # Area name (A)
    ))

    ## TODO: implement checks for constants (BusType, smth else)
    noItems+=1
catch
    msgWrongFormat(lineCounter,"line parsing error")
    return nothing
end


elseif readingMode == "TIE LINES"
MBusNum = parse(Int, line[1:4])
if MBusNum < 0
    # end of the section encountered
    noItems != noItems_exp ? warn("Warning: no. of items does not coincide with the ITEMS statement in the section head (",readingMode,") -- ",noItems_exp," expected, ",noItems," collected") : nothing
    readingMode="INIT"
    continue
end

try
    tie = vcat(tie, DataFrame(
        MBusNum = MBusNum,
        NAreaNum = parse(Int,line[7,8]),
        NMBusNum = parse(Int,line[11,14]),
        NMAreaNum= parse(Int,line[17,18]),
        CircuitNum = parse(Int,line[21]) #     Circuit number
    ))

    ## TODO: implement checks for constants (BusType, smth else)
    noItems+=1
catch
    msgWrongFormat(lineCounter,"line parsing error")
    return nothing
end


end # if (selecting modes)
end # if (checking for data-section end)
lineCounter+=1
end # for (going through lines)

end # do

return IEEE_CDF(bus,branch,loss_zones,interchange,tie)

end # function

end # module
