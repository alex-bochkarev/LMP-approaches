using JuMP
using Cbc

import IEEE_CDF_parser
reload("IEEE_CDF_parser")

# IEEE_CDF_parser.parse_cdf("../data/ign.ieee118cdf.txt")

# let us design a simplistic three-node test case:
buses = DataFrame(BusNo = [1,2,3], # bus number
                  Pmin = [0,0,0], # min supply
                  Pmax = [10,5,0], # max supply
                  Dmax = [0,0,7], # max demand
                  b = [0,0,20], # consumers' utility per kWh
                  C = [5,3,0], # costs per kWh
                  cSU = [0,0,0]) # startup costs

branches = DataFrame(Arc = ["a","b","c"], TapBusNo = [1, 2, 1], ZBusNo = [2,3,3], x=[1,1,1])

NIM = IEEE_CDF_parser.makeNIMatrix(size(buses,1), branches)

## ================== OPF model definition =====================
UC = JuMP.Model(solver=CbcSolver())
Nbus = size(buses,1)
Nbranches = size(branches,1)

# constants
const Fmax = 100
Pmax = maximum(buses[:,:Pmax])
Dmax = maximum(buses[:,:Dmax])

@defVar(UC, -Fmax <= f[l=1:Nbranches] <= Fmax) # flow through each branch l \in Branches (bd)
@defVar(UC, 0 <= p[i=1:Nbus] <= Pmax, Cont) # production
@defVar(UC, 0<= d[i=1:Nbus] <= Dmax) # consumption
@defVar(UC, z[i=1:Nbus], Bin) # generators' commitment (binary)
@defVar(UC, 0 <= theta[i=1:Nbus] <= 2*pi) # phase angle

for i=1:Nbus
    @addConstraint(UC, p[i] + sum{NIM[i,l] * f[l], l=1:Nbranches} == d[i]) # flow constraints
    @addConstraint(UC, p[i] >= z[i]*buses[i,:Pmin]) # min production
    @addConstraint(UC, p[i] <= z[i]*buses[i,:Pmax]) # max production

    @addConstraint(UC, d[i] <= buses[i, :Dmax])
end

for i=1:Nbranches
    @addConstraint(UC, f[i] == (1/branches[i,:x])*sum{-NIM[j,i]*theta[j],j=1:Nbus}) # line flow expression, DC-approximation
end

@addConstraint(UC, theta[1] == 0) # slack node


@setObjective(UC, :Max, sum{buses[i,:b]*d[i], i=1:Nbus} - sum{buses[j,:C]*p[j]+buses[j,:cSU]*z[j],j=1:Nbus})

# check the final model
UC

status = solve(UC)
println("Objective value = ", getObjectiveValue(UC))

println("Actual demand = ", getValue(d))
println("Supply = ", getValue(p))
println("Commitment flag = ", getValue(z))
println("theta = ", getValue(theta))
println("flows = ", getValue(f))
end
