#'log marginal likelihood of normal mean model
#'@param x data vector of length n
#'@param s standard error
#'@param w prior weights
#'@param grid grid of sd in prior
#'@return a vector of length n
l_nm = function(x,s,w,grid){
  return(log(f_nm(x,s,w,grid)))
}

#'@return a n by K matrix of normal density
nm_density = function(x,s,grid){
  K = length(grid)
  sdmat = sqrt(outer(s^2,grid^2,FUN="+"))
  return(stats::dnorm(outer(x,rep(1,K),FUN="*")/sdmat)/sdmat)
}

#'@return a vector of likelihood, of length n
f_nm = function(x,s,w,grid){
  return(c(nm_density(x,s,grid)%*%w))
}

# n = 100000
# x = 1:n
# t1 = Sys.time();a = matrix(x,nrow=n,ncol=200,byrow=FALSE);Sys.time()-t1
# t1 = Sys.time();a = outer(x,rep(1,200));Sys.time()-t1

# l_nm_d1 = function(x,w,grid){
#   s = sqrt(exp(-x))
#   f = sum(w*dnorm(x,0,sqrt(grid^2+s^2)))
#   f_d1 = sum(w*dnorm(x,0,sqrt(grid^2+s^2))*x/(grid^2+s^2))
#   f_d1/f
# }

#'@return a vector of gradient df/dz, length n
f_nm_d1_z = function(x,s,w,grid){
  vmat = outer(s^2,grid^2,FUN="+")
  return(c(-(nm_density(x,s,grid)/vmat*x)%*%w))
}

#'@return a vector of second derivative d^2f/dz^2, length n
f_nm_d2_z = function(x,s,w,grid){
  vmat = outer(s^2,grid^2,FUN="+")
  return(c((nm_density(x,s,grid)*(x^2/vmat^2-1/vmat))%*%w))
}

#'@return a vector of derivative dl_nm/dz, length n
l_nm_d1_z = function(x,s,w,grid){
  return(f_nm_d1_z(x,s,w,grid)/f_nm(x,s,w,grid))
}

#'@return a vector of second derivative d^2l_nm/dz^2, length n
l_nm_d2_z = function(x,s,w,grid){
  temp = f_nm(x,s,w,grid)
  return(f_nm_d2_z(x,s,w,grid)/temp - (f_nm_d1_z(x,s,w,grid)/temp)^2)
}

#'@return a vector of derivative df_nm/ds2, length n
f_nm_d1_s2 = function(x,s,w,grid){
  K = length(grid)
  xmat = outer(x,rep(1,K),FUN="*")
  vmat = outer(s^2,grid^2,FUN="+")
  return(c((nm_density(x,s,grid)/vmat^2*(xmat-vmat))%*%w/2))
}

#'@return a vector of second derivative d^2f_nm/dzds2, length n
f_nm_d2_zs2 = function(x,s,w,grid){
  K = length(grid)
  xmat = outer(x,rep(1,K),FUN="*")
  vmat = outer(s^2,grid^2,FUN="+")
  return(c((xmat*(3*vmat-xmat^2)/vmat^3.5*exp(-xmat^2/2/vmat))%*%w/2/sqrt(2*pi)))
}

#'@return a vector of derivative dl_nm/ds2, length n
l_nm_d1_s2 = function(x,s,w,grid){
  return(f_nm_d1_s2(x,s,w,grid)/f_nm(x,s,w,grid))
}

#'@return a vector of second derivative d^2l_nm/dzds2, length n
l_nm_d2_zs2 = function(x,s,w,grid){
  temp = f_nm(x,s,w,grid)
  return(f_nm_d2_zs2(x,s,w,grid)/temp-f_nm_d1_s2(x,s,w,grid)*f_nm_d1_z(x,s,w,grid)/temp^2)
}


#'@return a matrix of gradient, size n* K
f_nm_d1_a = function(x,s,a,grid){
  n = length(x)
  dens_mat = nm_density(x,s,grid)
  return((dens_mat*sum(exp(a)) - c(dens_mat%*%exp(a)))*outer(rep(1,n),exp(a))/sum(exp(a))^2)
}

#'@return a matrix of gradient, size n*K
f_nm_d2_za = function(x,s,a,grid){
  K = length(grid)
  xmat = outer(x,rep(1,K),FUN="*")
  vmat = outer(s^2,grid^2,FUN="+")
  dens_mat = nm_density(x,s,grid)
  lhs = c((dens_mat/vmat)%*%exp(a))
  rhs = (dens_mat/vmat)*sum(exp(a))
  return(outer(x,exp(a))*(lhs-rhs)/sum(exp(a))^2)

}

#'@return a matrix of gradient, size n*K
l_nm_d1_a = function(x,s,a,grid){
  w = softmax(a)
  return(f_nm_d1_a(x,s,a,grid)/f_nm(x,s,w,grid))
}

#'@return a matrix of gradient, size n*K
l_nm_d2_za = function(x,s,a,grid){
  w = softmax(a)
  temp = f_nm(x,s,w,grid)
  return(f_nm_d2_za(x,s,a,grid)/temp - f_nm_d1_a(x,s,a,grid)*f_nm_d1_z(x,s,w,grid)/temp^2)
}




softmax = function(a){
  exp(a-max(a))/sum(exp(a-max(a)))
}

#'posterior mean operator
S = function(x,s,w,grid){
  K = length(w)
  #s = sqrt(exp(-x))
  g = normalmix(pi=w,mean=rep(0,K),sd=grid)
  return(ashr:::calc_pm())
  fit.ash = ashr::ash(x,s,g=g,fixg=T)
  fit.ash$result$PosteriorMean
}

#'@title inverse operator of S
#'@describeIn S^{-1}(theta) returns the z such that S(z) = theta
S_inv = function(theta,s,w,grid,z_range,n_search_intval=100){
  #zs = seq(z_range[1],z_range[2],length.out = n_search_intval)
  #theta_vec = S(zs,s,w,grid)
  obj = function(z,theta,s,w,grid){
    return(z+s^2*l_nm_d1_z(z,s,w,grid)-theta)
  }
  n = length(theta)
  z_out = double(n)
  for(j in 1:n){
    if(theta[j]>=0){
      z_out[j] = uniroot(obj,c(theta[j],z_range[2]),theta=theta[j],s=s[j],w=w,grid=grid,extendInt = 'upX')$root
    }else{
      z_out[j] = uniroot(obj,c(z_range[1],theta[j]),theta=theta[j],s=s[j],w=w,grid=grid,extendInt = 'downX')$root
    }

  }
  z_out
}