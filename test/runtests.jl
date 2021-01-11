using Distributed
addprocs(2)

@everywhere using SPHtoGrid, Test, DelimitedFiles, SPHKernels

@testset "SPHtoGrid" begin

    @testset "Smac utility" begin

        @test_nowarn write_smac1_par("", 0, "", "", "", "",
                                        0, 0, 0, 4, 3,
                                        20.0, 10.0, 1, 1,
                                        24, 1.0, 1.e6, 10,
                                        1, 0.0, 0.0, 0.0)

        # @test_throws ErrorException("Read error: Incorrect image format!") read_smac1_binary_image(joinpath(dirname(@__FILE__), "snap_050"))

        filename = joinpath(dirname(@__FILE__), "Smac1.pix")
        info = read_smac1_binary_info(filename)

        @test info.snap == 140

        image = read_smac1_binary_image(filename)
        @test length(image[:,1]) == 128
        @test image[1,1] ≈ 0.000120693

        @test_nowarn write_smac1_par("", 0, "", "", "", "",
                                        0, 0, 0, 0, 0, 0.0, 0.0, 
                                        1, 1, 0, 1.0, 1.e6, 10, 0, 0.0, 0.0, 0.0)

        @test_nowarn write_smac2_par(1.0, 1.0, 1.0, 1.0, 1.0, 1.0,
                                        1.0, 1.0, 1024,
                                        "", "", "")
    end

    @testset "SPH mappingParameters" begin

        @test_throws ErrorException("Giving a center position requires extent in x, y and z direction.") mappingParameters()
        
        @test_throws ErrorException("Please specify pixelSideLenght or number of pixels!") mappingParameters(center=[0.0, 0.0, 0.0],
                                                                                        x_lim = [-1.0, 1.0],
                                                                                        y_lim = [-1.0, 1.0],
                                                                                        z_lim = [-1.0, 1.0])

        @test_nowarn mappingParameters(center=[0.0, 0.0, 0.0],
                                        x_lim = [-1.0, 1.0],
                                        y_lim = [-1.0, 1.0],
                                        z_lim = [-1.0, 1.0],
                                        Npixels=100)

        @test_nowarn mappingParameters(center=[0.0, 0.0, 0.0],
                                        x_lim = [-1.0, 1.0],
                                        y_lim = [-1.0, 1.0],
                                        z_lim = [-1.0, 1.0],
                                        pixelSideLength=0.2)
    end

    @testset "Filter particles" begin
        
        par = mappingParameters(center = [3.0, 3.0, 3.0],
                                x_size = 6.0, y_size = 6.0, z_size = 6.0,
                                Npixels = 500)

        x = zeros(3, 2)
        x[:,1] = [  1.0,  1.0, 1.0]
        x[:,2] = [ -3.0, -1.0, 1.0]

        hsml = [0.5, 0.5]

        p_in_image = filter_particles_in_image(x, hsml, par)

        @test p_in_image[1] == true
        #@test p_in_image[2] == false

    end

    @testset "Shift particles" begin
        
        par = mappingParameters(center = [1.0, 1.0, 1.0],
                                x_size = 6.0, y_size = 6.0, z_size = 6.0,
                                Npixels = 500)

        x = zeros(3, 2)
        x[:, 1] = [  1.0,  1.0, 1.0]
        x[:, 2] = [ -3.0, -1.0, 1.0]

        hsml = [0.5, 0.5]

        x, par2 = SPHtoGrid.check_center_and_move_particles(x, par)

        @test x[:, 1] ≈ [ 0.0, 0.0, 0.0]
        @test x[:, 2] ≈ [ -4.0, -2.0, 0.0]

        @test par.center ≈ [ 1.0, 1.0, 1.0 ]
        @test par2.center ≈ [ 0.0, 0.0, 0.0 ]

    end

    @testset "Rotate particles" begin
        
        # no rotation
        x_in = [1.0, 1.0, 1.0]
        x_out = SPHtoGrid.rotate_3D_quantity(x_in, 0.0, 0.0, 0.0)
        @test x_out ≈ x_in

        # matrix no rotation
        x_rand = rand(3, 10)
        x_out = rotate_3D(x_rand, 0.0, 0.0, 0.0)
        @test x_out ≈ x_rand

        # inplace
        rotate_3D!(x_out, 0.0, 0.0, 0.0)
        @test x_out ≈ x_rand

        # project along axis
        x_in = [1.0 1.0
                1.0 1.0
                0.0 0.0 ] 

        # along z-axis should not change anything
        x_out = project_along_axis(x_in, 3)

        @test x_out ≈ x_in

        # along y-axis
        x_out = project_along_axis(x_in, 2)

        # @test x_out ≈ copy(transpose([ 1.0 0.0 1.0
        #                                 1.0 0.0 1.0 ]))

        @test x_out ≈ [ 1.0 1.0
                        0.0 0.0
                        1.0 1.0 ] 

        # along x-axis
        x_out = project_along_axis(x_in, 2)

        @test x_out ≈ copy(transpose([ 1.0 0.0 1.0
                                        1.0 0.0 1.0 ]))
    end

    @testset "SPH Mapping" begin

        @info "SPH Mapping tests take a while..."

        @info "Data read-in."

        fi = joinpath(dirname(@__FILE__), "bin_q.txt")
        bin_quantity = Float32.(readdlm(fi))

        fi = joinpath(dirname(@__FILE__), "x.txt")
        x = copy(transpose(Float32.(readdlm(fi))))

        fi = joinpath(dirname(@__FILE__), "rho.txt")
        rho = Float32.(readdlm(fi))

        fi = joinpath(dirname(@__FILE__), "hsml.txt")
        hsml = Float32.(readdlm(fi))

        fi = joinpath(dirname(@__FILE__), "m.txt")
        m = Float32.(readdlm(fi))

        kernel = WendlandC6()

        par = mappingParameters(center = [3.0, 3.0, 3.0],
                        x_size = 6.0, y_size = 6.0, z_size = 6.0,
                        Npixels = 200,
                        boxsize = 6.0)

        @info "2D"

        @info "Single core."
        d = sphMapping(x, hsml, m, rho, bin_quantity, rho,
                            param=par, kernel=kernel,
                            parallel = false,
                            show_progress=true)


        ideal_file = joinpath(dirname(@__FILE__), "image.dat")
        d_ideal = readdlm(ideal_file)

        @test d[  1,  1] ≈ d_ideal[1, 1]
        @test d[ 30, 32] ≈ d_ideal[30, 32]
        #@test d[117, 92] ≈ d_ideal[117, 92]


        @info "Multi core."
        @test_nowarn sphMapping(x, hsml, m, rho, bin_quantity, ones(length(rho)),
                            param=par, kernel=kernel,
                            parallel = true,
                            show_progress=false)

        @info "3D"

        par = mappingParameters(center = [3.0, 3.0, 3.0],
                        x_size = 6.0, y_size = 6.0, z_size = 6.0,
                        Npixels = 10,
                        boxsize = 6.0)
        
        @info "Single core."
        d = sphMapping(x, hsml, m, rho, bin_quantity, ones(length(rho)),
                            param=par, kernel=kernel,
                            parallel = false,
                            show_progress=true,
                            dimensions=3)

        @test !isnan(d[1,1,1])

        @info "Multi core."
        @test_nowarn sphMapping(x, hsml, m, rho, bin_quantity, ones(length(rho)),
                            param=par, kernel=kernel,
                            parallel = true,
                            show_progress=false,
                            dimensions=3)

    end

    @testset "TSC Mapping" begin

        fi = joinpath(dirname(@__FILE__), "x.txt")
        x = Float32.(readdlm(fi))

        fi = joinpath(dirname(@__FILE__), "bin_q.txt")
        bin_quantity = Float32.(readdlm(fi))


        par = mappingParameters(center = [3.0, 3.0, 3.0],
                        x_size = 6.0, y_size = 6.0, z_size = 6.0,
                        Npixels = 200,
                        boxsize = 6.0)

        d = sphMapping( x, bin_quantity, 
                        param=par, show_progress=true)

        @test !isnan(d[1,1])

        @test_nowarn sphMapping( x, bin_quantity, 
                        param=par, show_progress=false)


        @test_nowarn sphMapping( x, bin_quantity, 
                        param=par, show_progress=false,
                        dimensions=3)

    end

    @testset "FITS io" begin
       
        # map data
        fi = joinpath(dirname(@__FILE__), "bin_q.txt")
        bin_quantity = Float32.(readdlm(fi))

        fi = joinpath(dirname(@__FILE__), "x.txt")
        x = copy(transpose(Float32.(readdlm(fi))))

        fi = joinpath(dirname(@__FILE__), "rho.txt")
        rho = Float32.(readdlm(fi))

        fi = joinpath(dirname(@__FILE__), "hsml.txt")
        hsml = Float32.(readdlm(fi))

        fi = joinpath(dirname(@__FILE__), "m.txt")
        m = Float32.(readdlm(fi))

        kernel = WendlandC6()

        par = mappingParameters(center = [3.0, 3.0, 3.0],
                        x_size = 6.0, y_size = 6.0, z_size = 6.0,
                        Npixels = 200,
                        boxsize = 6.0)

        d = sphMapping(x, hsml, m, rho, bin_quantity, ones(length(rho)),
                            param=par, kernel=kernel,
                            parallel = false,
                            show_progress=false)

        # store image in a file
        fits_file = joinpath(dirname(@__FILE__), "image.fits")

        @test_nowarn write_fits_image(fits_file, d, par)

        # read image back into memory and compare
        # image, fits_par, snap = read_fits_image(fits_file)

        # @test image ≈ d 
        # @test par.boxsize == fits_par.boxsize
        # @test par.center == fits_par.center


    end

    @testset "Reconstructing Grid" begin
        par = mappingParameters(center = [3.0, 3.0, 3.0],
                        x_size = 6.0, y_size = 6.0, z_size = 6.0,
                        Npixels = 200,
                        boxsize = 6.0)

        @test_nowarn get_map_grid_2D(par)
        @test_nowarn get_map_grid_3D(par)
    end

    @testset "Weight functions" begin

        weight = part_weight_one(1)
        @test weight[1] == 1.0

        par = mappingParameters(center = [3.0, 3.0, 3.0],
                        x_size = 6.0, y_size = 6.0, z_size = 6.0,
                        Npixels = 200,
                        boxsize = 6.0)

        weight = part_weight_physical(1, par)
        @test weight[1] == par.pixelSideLength

        weight = part_weight_emission([0.5, 0.5], [0.5, 0.5])
        @test weight[1] ≈ 0.1767766952966369

        # weight = part_weight_spectroscopic([0.5, 0.5], [0.5, 0.5])
        # @test weight[1] ≈ 0.42044820762685725

        # weight = part_weight_XrayBand([0.5, 0.5], 0.5, 1.5)
        # @test weight[1] ≈ 0.0


    end

    @testset "Effect functions" begin

        @test density_2D(1.0, 1.0) ≈ 2.088976598481755

        @test SPHtoGrid.Tcmb(0.0)  ≈ 2.728
        @test SPHtoGrid.Tcmb(10.0) ≈ 30.008000000000003

        @test kinetic_SZ(1.0, 1.0) ≈ -2.2190366589946296e-35

        @test thermal_SZ(1.0, 1.0) ≈ 3.876935843260665e-34

        @test x_ray_emission(1.0, 1.0e8) ≈ 4.87726213161308e-26
       
        @test x_ray_emission(1.0, 1.0e9) ≈ 2.8580049510920225e-23

        @test analytic_synchrotron_emission([1.0], [1.0], [1.0], [10.0])[1] ≈ 6.519225967570028e-25

        @test analytic_synchrotron_emission([1.0], [1.0], [1.0], [1.0])[1] == 0.0

        @test_throws ErrorException("Invalid DSA model selection!") analytic_synchrotron_emission([1.0], [1.0], [1.0], [1.0], dsa_model=10)

    end

    @testset "DSA models" begin
        # KR07
        @test SPHtoGrid.KR07_acc(5.0) ≈ 0.25185919999999995
        # KR13
        @test SPHtoGrid.KR13_acc( 5.0) ≈ 0.09999999999999998
        @test SPHtoGrid.KR13_acc(10.0) ≈ 0.19631644350722818
        @test SPHtoGrid.KR13_acc(25.0) ≈ 0.21152
        # Ryu+19
        @test SPHtoGrid.Ryu19_acc( 5.0) ≈ 0.017286554080677037
        @test SPHtoGrid.Ryu19_acc(55.0) ≈ 0.0348
        # CS14
        @test SPHtoGrid.CS14_acc(5.0) ≈ 0.04999999999999999
        # Pfrommer+16
        @test SPHtoGrid.P16_acc(5.0) == 0.5
    end
end