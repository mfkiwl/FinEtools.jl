using FinEtools
using FinEtools.MeshExportModule

println("LE1NAFEMS, 2D version."        )
t0 = time()

E = 210e3*phun("MEGA*PA");
nu = 0.3;
p = 10*phun("MEGA*PA");# 10 MPA Outward pressure on the outside ellipse
sigma_yD = 92.7*phun("MEGA*PA");# tensile stress at [2.0, 0.0] meters
Radius = 1.0*phun("m")
Thickness = 0.1*phun("m")


sigyderrs = Dict{Symbol, FFltVec}()
nelems = []

for extrapolation in [:default]
    sigyderrs[extrapolation] = FFltVec[]
    nelems = []
    for n in [16, 32, 64, 128, 256, 512]
        tolerance = 1.0/n/1000.; # Geometrical tolerance

        fens,fes = Q4block(1.0, pi/2, n, n)

        bdryfes = meshboundary(fes);
        icl = selectelem(fens, bdryfes, box=[1.0, 1.0, 0.0, pi/2], inflate=tolerance);
        for i=1:count(fens)
            t=fens.xyz[i,1]; a=fens.xyz[i,2];
            fens.xyz[i,:]=[(t*3.25+(1-t)*2)*cos(a), (t*2.75+(1-t)*1)*sin(a)];
        end


        geom = NodalField(fens.xyz)
        u = NodalField(zeros(size(fens.xyz,1), 2)) # displacement field

        l1 =selectnode(fens; box=[0.0, Inf, 0.0, 0.0], inflate = tolerance)
        setebc!(u,l1,true, 2, 0.0)
        l1 =selectnode(fens; box=[0.0, 0.0, 0.0, Inf], inflate = tolerance)
        setebc!(u,l1,true, 1, 0.0)

        applyebc!(u)
        numberdofs!(u)


        el1femm =  FEMMBase(GeoD(subset(bdryfes,icl), GaussRule(1, 2), Thickness))
        function pfun(forceout::FVec{T}, XYZ::FFltMat, tangents::FFltMat, fe_label::FInt) where {T}
            pt= [2.75/3.25*XYZ[1], 3.25/2.75*XYZ[2]]
            forceout .=    vec(p*pt/norm(pt));
            return forceout
        end
        fi = ForceIntensity(FFlt, 2, pfun);
        F2 = distribloads(el1femm, geom, u, fi, 2);

        # Note that the material object needs to be created for plane stress.
        MR = DeforModelRed2DStress

        material = MatDeforElastIso(MR, E, nu)

        femm = FEMMDeforLinear(MR, GeoD(fes, GaussRule(2, 2), Thickness), material)

        # The geometry field now needs to be associated with the FEMM
        femm = associategeometry!(femm, geom)

        K = stiffness(femm, geom, u)
        K = cholfact(K)
        U = K\(F2)
        scattersysvec!(u, U[:])

        nl = selectnode(fens, box=[2.0, 2.0, 0.0, 0.0],inflate=tolerance);
        thecorneru = zeros(FFlt,1,2)
        gathervalues_asmat!(u, thecorneru, nl);
        thecorneru = thecorneru/phun("mm")
        println("$(time()-t0) [s];  displacement =$(thecorneru) [MM] as compared to reference [-0.10215,0] [MM]")


        fld = fieldfromintegpoints(femm, geom, u, :Cauchy, 2)
        println("Sigma_y =$(fld.values[nl,1][1]/phun("MPa")) vs $(sigma_yD/phun("MPa")) [MPa]")

        println("$(n), $(fld.values[nl,1][1]/phun("MPa"))")
        push!(nelems, count(fes))
        push!(sigyderrs[extrapolation], abs(fld.values[nl,1][1]/sigma_yD - 1.0))
        #     File =  "a.vtk"
        # vtkexportmesh(File, fes.conn, geom.values,
        #                FinEtools.MeshExportModule.H8; vectors=[("u", u.values)],
        #                scalars=[("sigmay", fld.values)])
        # @async run(`"paraview.exe" $File`)
    end
end


using DataFrames
using CSV

df = DataFrame(nelems=vec(nelems),
    sigyderrdefault=vec(sigyderrs[:default]))
File = "LE1NAFEMS_Q4_convergence.CSV"
CSV.write(File, df)
@async run(`"paraview.exe" $File`)