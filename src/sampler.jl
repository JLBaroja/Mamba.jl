#################### MCMCSampler Constructor ####################

function MCMCSampler(params::Vector, expr::Expr, tune::Dict=Dict())
  MCMCSampler(String[params...], String[], samplerfx(expr), tune)
end


#################### MCMCSampler Methods ####################

function Base.show(io::IO, s::MCMCSampler)
  print(io, "An object of type \"$(summary(s))\"\n")
  print(io, "Sampling Block Nodes:\n")
  show(io, s.params)
  print(io, "\n\n")
  show(io, s.eval.code)
  print(io, "\n")
end

function Base.showall(io::IO, s::MCMCSampler)
  show(io, s)
  print(io, "\nTuning Parameters:\n")
  show(io, s.tune)
  print(io, "\nDirectly Linked Nodes:\n")
  show(io, s.links)
  print(io, "\n")
end


#################### Adaptive Metropolis within Gibbs ####################

function SamplerAMM{T<:String}(params::Vector{T}, Sigma::Matrix;
                               adapt::Symbol=:none)
  any(adapt .== [:all, :burnin, :none]) ||
    error("adapt argument must be one of :all, :burnin, or :none")

  MCMCSampler(params,
    quote
      keys = blockkeys(model, block)
      x = unlist(model, keys)
      tunepar = blocktune(model, block)
      v = VariateAMM(x, tunepar["sampler"])
      adapt = tunepar["adapt"] == :burnin ? model.iter <= model.burnin :
              tunepar["adapt"] == :all ? true : false
      amm!(v, tunepar["Sigma"], logpdf!, model, block, adapt=adapt)
      tunepar["sampler"] = v.tune
      relist(model, v.data, keys)
    end,
    ["Sigma" => cholfact(Sigma), "adapt" => adapt, "sampler" => nothing]
  )
end


#################### Adaptive Metropolis within Gibbs ####################

function SamplerAMWG{T<:String}(params::Vector{T}, sigma::Vector;
                                adapt::Symbol=:none, batch::Integer=50,
                                target::Real=0.44)
  any(adapt .== [:all, :burnin, :none]) ||
    error("adapt argument must be one of :all, :burnin, or :none")

  MCMCSampler(params,
    quote
      keys = blockkeys(model, block)
      x = unlist(model, keys)
      tunepar = blocktune(model, block)
      v = VariateAMWG(x, tunepar["sampler"])
      adapt = tunepar["adapt"] == :burnin ? model.iter <= model.burnin :
              tunepar["adapt"] == :all ? true : false
      amwg!(v, tunepar["sigma"], logpdf!, model, block, adapt=adapt,
            batch=tunepar["batch"], target=tunepar["target"])
      tunepar["sampler"] = v.tune
      relist(model, v.data, keys)
    end,
    ["sigma" => sigma, "adapt" => adapt, "batch" => batch, "target" => target,
     "sampler" => nothing]
  )
end


#################### No-U-Turn Sampler ####################

function SamplerNUTS{T<:String}(params::Vector{T}, target::Real=0.6)
  MCMCSampler(params,
    quote
      keys = blockkeys(model, block)
      x = unlist(model, keys)
      tunepar = blocktune(model, block)
      v = VariateNUTS(x, tunepar["sampler"])
      if model.iter == 1
        tunepar["eps"] = nutseps(x, nutsfx!, model, block)
      end
      nuts!(v, tunepar["eps"], nutsfx!, model, block,
            adapt=model.iter <= model.burnin, target=tunepar["target"])
      tunepar["sampler"] = v.tune
      relist(model, v.data, keys)
    end,
    ["eps" => 1.0, "target" => target, "sampler" => nothing]
  )
end

function nutsfx!(x::Vector, m::MCMCModel, block::Integer)
  f = logpdf!(m, x, block)
  g = gradient!(m, x, block)
  f, g
end


#################### Multivariate Slice Sampler ####################

function SamplerSlice{T<:String}(params::Vector{T}, width::Vector)
  MCMCSampler(params,
    quote
      keys = blockkeys(model, block)
      x = unlist(model, keys)
      v = slice(x, blocktune(model, block)["width"], logpdf!, model, block)
      relist(model, v.data, keys)
    end,
    ["width" => width]
  )
end


#################### Slice within Gibbs Sampler ####################

function SamplerSliceWG{T<:String}(params::Vector{T}, width::Vector)
  MCMCSampler(params,
    quote
      keys = blockkeys(model, block)
      x = unlist(model, keys)
      v = slicewg(x, blocktune(model, block)["width"], logpdf!, model, block)
      relist(model, v.data, keys)
    end,
    ["width" => width]
  )
end


#################### Utility Functions ####################

function logpdf!(x::Vector, m::MCMCModel, block::Integer)
  logpdf!(m, x, block)
end

function samplerfx(expr::Expr)
  eval(Main, Expr(:function, :(model::MCMCModel, block::Integer), expr))
end