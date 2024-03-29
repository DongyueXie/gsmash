library(vebpm)

datax = gen_data_identity(n=1000,n_simu=30,prior='gamma')
res = simu_study_poisson_mean(datax,n_cores = 10)
saveRDS(res,file='output/poisson_mean_simulation/gamma_prior.rds')
saveRDS(datax,file='data/poisson_mean_simulation/gamma_prior.rds')

datax2 = gen_data_identity(n=1000,n_simu=30,prior='t',t_delta=2)
res2 = simu_study_poisson_mean(datax2,n_cores = 8)
saveRDS(res2,file='output/poisson_mean_simulation/t_prior_delta2.rds')
saveRDS(datax2,file='data/poisson_mean_simulation/t_prior_delta2.rds')

datax3 = gen_data_exp(n=1000,n_simu=30,prior_mean=3,prior_var0 = 0, prior_var1 = 2)
res3 = simu_study_poisson_mean(datax3,n_cores = 8)
saveRDS(res3,file='output/poisson_mean_simulation/exp_mean3var2.rds')
saveRDS(datax3,file='data/poisson_mean_simulation/exp_mean3var2.rds')
