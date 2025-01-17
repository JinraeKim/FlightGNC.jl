abstract type AbstractBPNG <: AbstractController end

mutable struct BPNG <: AbstractBPNG
    N::Float64
    dim::Int
    α::Float64
    σ_M_lim::Float64
    v̂_f_d::Vector
    Bias::Function
    s_Bias
end

function BPNG_cmd(s_guidance::BPNG)
    @unpack N, dim, Bias = s_guidance
    return function (x, params, t)
        (p_M, v_M, p_T, v_T) = (x.pursuer.p, x.pursuer.v, x.evador.p , x.evador.v)
        if dim == 2
            (p_M, v_M, p_T, v_T) = vcat.((p_M, v_M, p_T, v_T), 0)
        end

        ω_r      = cross(p_T - p_M, v_T - v_M) / dot(p_T - p_M, p_T - p_M)
        a_M_PPNG = N * cross(ω_r, v_M)
        a_M_bias = Bias(s_guidance, x, t)
        
        a_M      = a_M_PPNG + a_M_bias
        
        # if norm(a_M) >= A_M_max
        #     a_M = normalize(a_M) * min(max(norm(a_M), -A_M_max), A_M_max)
        # end
        if dim == 2
            a_M = a_M[1:2]
        end

        return a_M
    end
end

function nzero_sign(x)
    if x >= 0
        y = 1
    else
        y = -1
    end
    return y
end

function Bias_zero(s_guidance::BPNG, x, t)
    return zeros(3)
end

function Bias_IACG_StationaryTarget(s_guidance::BPNG, x, t)
    @unpack N, dim, α, σ_M_lim, v̂_f_d, s_Bias = s_guidance
    @unpack δ, n, r_ref, k, m = s_Bias
    (p_M, v_M, p_T, v_T) = (x.pursuer.p, x.pursuer.v, x.evador.p, x.evador.v)
    if dim == 2
        (p_M, v_M, p_T, v_T) = vcat.((p_M, v_M, p_T, v_T), 0)
    end
    # @assert norm(v_T) < 0.1

    function K_e(r, N; δ = 0.01, n = 0, r_ref = Inf)
        # K_e@vec_BPNG = K_r@LCG_e_0 / (N - 1) / r
        return (N - 1 + δ) / (N - 1) / r * (1 + (r / r_ref)^n)
    end

    function K_roll(r)
        return 0
    end

    function K_σ(σ_M, σ_M_lim; k = 0, m = 0)
        η     = sin(σ_M)
        η_lim = sin(σ_M_lim)
        return 1 + k * (1 - (abs(η / η_lim))^m)
    end

    r        = norm(p_T - p_M)
    r̂        = normalize(p_T - p_M)
    ṙ        = dot(r̂, v_T - v_M)
    v̂_M      = normalize(v_M)
    σ_M      = acos(dot(r̂, v̂_M))
    k̂        = cross(r̂, v̂_M) # k̂ = normalize(cross(p_T - p_M, v_M))
    v̂_f_pred = v̂_M * cos(N / (N - 1) * σ_M) - cross(k̂, v̂_M) * sin(N / (N - 1) * σ_M)
    e_v̂_f    = acos(dot(v̂_f_pred, v̂_f_d))
    ω_f      = -K_e(r, N) * ṙ * e_v̂_f^α * normalize(cross(v̂_f_pred, v̂_f_d)) + K_roll(r) * v̂_f_d
    ω_bias   = K_σ(σ_M, σ_M_lim) * ( -(N - 1) * dot(ω_f, k̂) * k̂ + sin(σ_M) * dot(ω_f, r̂ + cot(1 / (N-1) * σ_M) * cross(k̂, r̂)) * cross(v̂_M, k̂) )

    if dim == 2  # identical to the codes above, thus can be deleted
        k̂     = [0; 0; 1]      
        e_v̂_f_signed = atan(dot(v̂_f_pred, cross(k̂, v̂_f_d)), dot(v̂_f_pred, v̂_f_d))
        ω_f     = K_e(r, N) * ṙ  * nzero_sign(e_v̂_f_signed) * abs(e_v̂_f_signed)^α * k̂
        ω_bias  = K_σ(σ_M, σ_M_lim) * ( -(N - 1) * ω_f )
    end

    a_M_bias = cross(ω_bias, v_M)

    return a_M_bias
end


function Bias_IACG_StationaryTarget_2D(s_guidance::BPNG, x, t)
    @unpack N, dim, α, σ_M_lim, v̂_f_d, s_Bias = s_guidance
    @unpack δ, n, r_ref, k, m = s_Bias
    (p_M, v_M, p_T, v_T) = (x.pursuer.p, x.pursuer.v, x.evador.p, x.evador.v)
    r       = norm(p_T-p_M)
    λ       = atan(p_T[2]-p_M[2], p_T[1]-p_M[1])   
    
    V_M     = norm(v_M)
    γ_M     = atan(v_M[2], v_M[1])
    σ_M     = γ_M - λ
    η       = sin(σ_M)
    η_lim   = sin(σ_M_lim)

    # V_T     = norm(v_T)
    # γ_T     = atan(v_T[2], v_T[1])
    # σ_T     = γ_T - λ

    γ_f_d   = atan(v̂_f_d[2], v̂_f_d[1])

    # λ̇       = (V_T*sin(σ_T) - V_M*sin(σ_M)) / r        
    e_γ_f   = γ_M - N / (N - 1) * σ_M - γ_f_d;
    if α > 0.99
        e_γ_f_fbk = e_γ_f
    else
        e_γ_f_fbk = nzero_sign(e_γ_f)*abs(e_γ_f)^α
    end

    K_r     = (N - 1 + δ) * (1 + r / r_ref)^n ;
    K_eta   = 1 + k * (1 - (abs(η / η_lim))^m);
    u_aug = - K_r * K_eta / r * e_γ_f_fbk
    
    A_M_bias = - u_aug * V_M^2 * cos(σ_M)
    a_M_bias = A_M_bias * [-sin(γ_M); cos(γ_M); 0]

    # A_M_PPNG = N * V_M * λ̇ 
    # A_M = A_M_PPNG + A_M_bias
    # A_M = min(max(A_M, -A_M_max), A_M_max)

    return a_M_bias
end






"""
obsolete legacy
"""
# function GuidanceLaw(s_guidance::BPNG)
#  """
#  u_pursuer=GuidanceLaw(s_guidance)
#  """
#     bpng_law = Command(s_guidance)
#     return function (x, params, t)
#         p_M = x.pursuer.p
#         v_M = x.pursuer.v
#         p_T = x.evador.p
#         v_T = x.evador.v
#         bpng_law(p_M, v_M, p_T, v_T)
#     end
# end

# function Command(s_guidance::BPNG)
#     @unpack N, dim, α, σ_M_lim, v̂_f_d, s_Bias = s_guidance
#     @unpack δ, n, r_ref, k, m = s_Bias
#     # δ, n, r_ref, k, m = 0.01, 1, 10E3, 9, 10
#     return function (p_M, v_M, p_T, v_T)
#         ~~~~
#     end
# end