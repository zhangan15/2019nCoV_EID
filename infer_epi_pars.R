## Infer the epidemic parameters in Wuhan per day: seed size i_0 and growth rate Lambda
## Final version at 2020/02/09
## Written by Dr. Lin Wang from the Mathematical Modelling of Infectious Diseases Unit, Institut Pasteur, UMR2000, CNRS, France
## Website: https://research.pasteur.fr/en/team/mathematical-modelling-of-infectious-diseases/
## Email: fdlwang@gmail.com; lin.wang@pasteur.fr

rm(list = ls())

setwd( " " )  # To Do: Specify the working directory !!!!
getwd()


## Install packages if necessary --------------------------------------

installed_package_details <- installed.packages()
installed_package_names    <- as.vector(installed_package_details[,1])
installed_package_versions <- as.vector(installed_package_details[,3])

# List of package dependencies
dependencies <- c(
  "pracma",
  "readr",
  "tibble",
  "dplyr",
  "purrr",
  "stringr",
  "rstan"
  )

# Install uninstalled dependencies
uninstalled_dependencies <- dependencies[!dependencies %in% installed_package_names]
lapply(uninstalled_dependencies, install.packages)


## Load packages -----------------------

library(pracma)
library(readr)
library(tibble)
library(dplyr)
library(purrr)
library(stringr)
library(ggridges)
library(rstan)

options(mc.cores = parallel::detectCores());
rstan_options(auto_write = TRUE);

## Monthly flight data is based on the following resources ------------------------------------------------------------------------------
## 1. Pneumonia of Unknown Etiology in Wuhan, China: Potential for International Spread Via Commercial Air Travel. J Travel Med (2020)
## 2. Nowcasting and forecasting the potential domestic and international spread of the 2019-nCoV outbreak originating in Wuhan, China: a modelling study, Lancet (2020) https://www.thelancet.com/journals/lancet/article/PIIS0140-6736(20)30260-9/fulltext
## 3. Preliminary risk analysis of 2019 novel coronavirus spread within and beyond China, https://www.worldpop.org/resources/docs/china/WorldPop-coronavirus-spread-risk-analysis-v1-25Jan.pdf

flight_mth = c(
  16202, # BKK, Bangkok,    Thailand 
  1816,  # CNX, Chiang Mai, Thailand
  30,    # KTM, Kathmandu,  Nepal
  947,   # HAN, Haoni,      Vietnam
  315,   # CHI, Chicago,    USA
  259,   # SEA, Seattle,    USA
  5661,  # SIN,             Singapore
  5982,  # ICN, Seoul,      Korea
  5269,  # HND, Tokyo,      Japan
  5261,  # TPE, Taipei,     Taiwan, China
  2504,  # SYD, Sydney,     Australia
  7531,  # HKG, Hong Kong,  China
  4411,  # HKT, PHUKET,     Thailand 
  4531,  # BKI, Kota Kinabalu, Sabah, Malaysia
  3731,  # MFM, Macau,      China
  2432,  # DPS, Bali,       Indonesia
  1799,  # DXB, Dubai,      United Arab Emirates
  1902,  # KUL, Kuala Lumpur, Malaysia
  2718,  # KHH, Kaohsiung,  Taiwan, China
  2636,  # ITM, Osaka,      Japan 
  1906,  # KBV, Krabi,      Thailand
  1898,  # MEL, Melbourne,  Australia
  1874.7, # URT, Surat Thani, Thailand
  1686.3, # PEN  Penang,    Malaysia
  3256,  # SGN, Ho Chi Minh City, Vietnam
  2000,  # PNH, Phnom Penh, Cambodia
  1924   # LON, London      UK
)

dur_1801to1803 = 30
daily_flight_18 = flight_mth / dur_1801to1803

names(daily_flight_18) <- c(
  "BKK",
  "CNX", # Chiang Mai
  "KTM",
  "HAN", # Haoni
  "CHI",
  "SEA",
  "SIN",
  "ICN",
  "HND",
  "TPE",
  "SYD",
  "HKG",
  "HKT",
  "BKI",
  "MFM",
  "DPS",
  "DXB",
  "KUL",
  "KHH",
  "ITM",
  "KBV",
  "MEL",
  "URT",
  "PEN",
  "SGN",
  "PNH",
  "LON"
)


W_BKK_day = unname( daily_flight_18[ str_which(names(daily_flight_18), "BKK") ] )
W_CNX_day = unname( daily_flight_18[ str_which(names(daily_flight_18), "CNX") ] )
W_KTM_day = unname( daily_flight_18[ str_which(names(daily_flight_18), "KTM") ] )
W_HAN_day = unname( daily_flight_18[ str_which(names(daily_flight_18), "HAN") ] )
W_CHI_day = unname( daily_flight_18[ str_which(names(daily_flight_18), "CHI") ] )
W_SEA_day = unname( daily_flight_18[ str_which(names(daily_flight_18), "SEA") ] )
W_SIN_day = unname( daily_flight_18[ str_which(names(daily_flight_18), "SIN") ] )
W_ICN_day = unname( daily_flight_18[ str_which(names(daily_flight_18), "ICN") ] )
W_HND_day = unname( daily_flight_18[ str_which(names(daily_flight_18), "HND") ] )
W_TPE_day = unname( daily_flight_18[ str_which(names(daily_flight_18), "TPE") ] )
W_SYD_day = unname( daily_flight_18[ str_which(names(daily_flight_18), "SYD") ] )

W_others_day = 3633 -
  W_BKK_day - W_CNX_day - W_KTM_day - W_HAN_day - W_CHI_day -
  W_SEA_day - W_SIN_day - W_ICN_day - W_HND_day - W_TPE_day -
  W_SYD_day;


## Inference of (1) initiall number of cases, and (2) epidemic growth rate from 2019/12/01 to 2020/01/22 -----------------
## We jointly estimate seed size and growth rate, so we don't require the exact starting time (e.g. ealier than 2010/12/01)

dur_detect = 10; # To Do: Change it for sensitivity analysis

idx_T_UB = 53;   # To Do: Change it according to the end time of studies period
x_0 = 31;  # To Do: start time of international surveillence

popSize_wuhan = 11.08 * 1e6;  # Population size of Wuhan

T_calndr_vec = seq(1, idx_T_UB);

## time step for integral
dt = 1/50 
n_dt = 1 / dt
dtVec = seq(0, idx_T_UB, by=dt)
T_dt_idxs_UB = seq(n_dt, length(dtVec), by=n_dt)

T_calndr_LB = c( rep(1, dur_detect), (dur_detect + 1):tail(T_calndr_vec, 1) - dur_detect + 1 )
T_dt_idxs_LB = sapply(
  T_calndr_LB - 1, 
  function (T_dt_LB, dtVec) which(dtVec == T_dt_LB),
  dtVec = dtVec
  ) 

stan_data <- list(
  "dur_detect" = dur_detect,
  "idx_T_UB" = idx_T_UB,
  "T_UB_real" = idx_T_UB,
  
  "x_0" = x_0,
  
  "idx_dtVec_UB" = length(dtVec),
  "dtVec" = dtVec,
  
  "T_dt_idxs_LB" = T_dt_idxs_LB, 
  "T_dt_idxs_UB" = T_dt_idxs_UB, 
  "dt" = dt,
  "popSize_wuhan" = popSize_wuhan,
  
  "W_BKK_day" = W_BKK_day,
  "W_CNX_day" = W_CNX_day,
  "W_KTM_day" = W_KTM_day,
  "W_HAN_day" = W_HAN_day,
  "W_CHI_day" = W_CHI_day,
  "W_SEA_day" = W_SEA_day,
  "W_SIN_day" = W_SIN_day,
  "W_ICN_day" = W_ICN_day,
  "W_HND_day" = W_HND_day,
  "W_TPE_day" = W_TPE_day,
  "W_SYD_day" = W_SYD_day,
  "W_global_day" = sum( daily_flight_18 ),
  
  "arr_time_BKK_1D" = c(39, 48, 50, 52),
  "arr_time_CNX" = 52, # Chiang Mai
  "arr_time_KTM" = 40,
  "arr_time_HAN" = 44,
  "arr_time_CHI" = 44,
  "arr_time_SEA" = 46,
  "arr_time_SIN" = 52,
  "arr_time_ICN_1D" = c(50, 53),
  "arr_time_HND_1D" = c(49, 50),
  "arr_time_TPE_1D" = c(51, 52, 52),
  "arr_time_SYD_1D" = c(49, 51)
  )


stan_filename  = paste(getwd(), "stan_infer_dIw_exp.stan", sep = .Platform$file.sep);
write_filename = paste(getwd(), "fit_pars", sep = .Platform$file.sep);

FOIfit <- stan(
  file = stan_filename,
  data = stan_data,
  init = "random",
  iter = 20000,
  warmup = 10000,
  chains = 10,
  thin = 1,
  sample_file = write_filename,
  cores =2,
  verbose = T,
  control = list(adapt_delta = 0.99, max_treedepth = 25)
  )


## compute posterior
quantile_vec <- c(0.5, 0.025, 0.975)

ChainResults <- extract(FOIfit)

n_seed_quantiles <- quantile(ChainResults$n_seed, quantile_vec)
growthRate_quantiles <- quantile(ChainResults$growthRate, quantile_vec)
doub_time = sort( log(2) / growthRate_quantiles )


## Estimate cumulative number of cases and reported cases by 2020/01/22
## To Do: Choose posterior 2.5%, 50%, 97.5% using index 1, 2, or 3

n_seed_esti = unname( n_seed_quantiles[3] )  
growthRate_esti = unname( growthRate_quantiles[3] )
dIw_u_vec_esti = n_seed_esti * exp( growthRate_esti * dtVec )

dt_detect_UB = tail(which(dtVec < idx_T_UB - dur_detect), 1)

cumINC = sum( dIw_u_vec_esti ) * dt;                        # cumulative number of cases by 2020/01/22
cumINC_detect = sum( dIw_u_vec_esti[1:dt_detect_UB] ) * dt  # cumulative number of cases reported by 2020/01/22, given the assumed lag between infection and detection D
  
## number of infectious cases per day Iw(t) from 2019/12/08 to 2020/01/22

Iw_T_vec = rep(0.0, idx_T_UB);

for ( idx_T in 1:idx_T_UB ) {
  T_dt_LB = T_dt_idxs_LB[idx_T];
  T_dt_UB = T_dt_idxs_UB[idx_T];
  Iw_T_vec[idx_T] = sum( dIw_u_vec_esti[ T_dt_LB : T_dt_UB ] ) * dt;
}


## Compute R0 by SEIR model ---------------------------------------------

LatentPeriod = 3:6
InfectPeriod = 2:6

idx = 1;
tar_growRate = growthRate_quantiles[idx]
R0_vec1 = mapply(
  function (latent_period, infect_period, growthRate) 
    { return( (1.0 + growthRate * latent_period) * (1.0 + growthRate * infect_period) ) },
  latent_period = rep( LatentPeriod, each=length(InfectPeriod) ),
  infect_period = rep( InfectPeriod, length(LatentPeriod) ),
  MoreArgs = list( growthRate = tar_growRate )
  )

idx = 2;
tar_growRate = growthRate_quantiles[idx]
R0_vec2 = mapply(
  function (latent_period, infect_period, growthRate) 
  { return( (1.0 + growthRate * latent_period) * (1.0 + growthRate * infect_period) ) },
  latent_period = rep( LatentPeriod, each=length(InfectPeriod) ),
  infect_period = rep( InfectPeriod, length(LatentPeriod) ),
  MoreArgs = list( growthRate = tar_growRate )
  )

idx = 3;
tar_growRate = growthRate_quantiles[idx]
R0_vec3 = mapply(
  function (latent_period, infect_period, growthRate) 
  { return( (1.0 + growthRate * latent_period) * (1.0 + growthRate * infect_period) ) },
  latent_period = rep( LatentPeriod, each=length(InfectPeriod) ),
  infect_period = rep( InfectPeriod, length(LatentPeriod) ),
  MoreArgs = list( growthRate = tar_growRate )
)

R0_vec = c(R0_vec1, R0_vec2, R0_vec3)


R0_esti = quantile( R0_vec, quantile_vec )  # posterior of R0






















