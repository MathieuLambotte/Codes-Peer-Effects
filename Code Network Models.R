#### Packages and options ####
if (!require("pacman")) install.packages("pacman")
pacman::p_load(pracma,keyplayer,nnet,CDatanet,modelsummary,prediction,estimatr,ivreg,RColorBrewer,Rlabkey,xfun,readxl,dplyr,tidyr,expm,truncnorm,foreach,parallel,igraph,rgl,rmarkdown,matrixcalc,installr,knitr,base64enc)
packages<-c("pracma","keyplayer","nnet","CDatanet","modelsummary","prediction","estimatr","xfun","ivreg","RColorBrewer","Rlabkey","readxl","dplyr","tidyr","expm","truncnorm","Matrix","MASS","foreach","igraph","rgl","highr","rmarkdown","matrixcalc","installr","knitr","base64enc")
lapply(packages, require, character.only = TRUE)
options(scipen=999)

#### Load or create data ####
#Specific for us
file_import<- function(filepath,matrix_output_name="G",graph_output_name="g",convert=FALSE,directed=FALSE,weighted_adjacency=FALSE,row_normalization=FALSE){
  
  file_path<-filepath
  
  #creating an object named 'dat', with the assignment operator, simply containing data of the excel file
  if(file_ext(file_path) == "csv"){
    read.csv(file=file_path, header=TRUE, sep=",")
  }
  if(file_ext(file_path) == "xlsx" | file_ext(file_path) == "xls"  ){
    dat <- read_excel(file_path,col_names = TRUE) }
  
  if(convert == TRUE){
    dat<-gather(dat,key=id1,value=id2,-identifiant,na.rm=TRUE)[,-2] }  #Different from Gallo's script to accommodate 
  dat<-dat[order(dat$identifiant),]%>%distinct() # equivalent to dat[,'identifiant']
  #our database
  #convert the raw data into an graph 
  g<-graph_from_data_frame(d = dat,directed = directed, vertices =NULL) #if directed = TRUE, asymmetric matrix, if directed = FALSE, symmetric matrix, reciprocal link are weighted 2 (="double link")
  assign((graph_output_name),g,envir=.GlobalEnv)
  if(weighted_adjacency==TRUE){
    G<-get.adjacency(g,attr = "weight", type = "both") 
  }
  if(weighted_adjacency==FALSE){
    G<-get.adjacency(g,sparse = T, type = "both") 
  }
  G<-as.matrix(G)
  #G[G=="2"]<-1 #If we want uniform weights for all kind of links, replace "2" by "1"
  
  if(row_normalization == TRUE){ #In original code from Habiba's website, weighted adjacency only if directed = FALSE
    #but currently I cannot see why 
    G<-round(G/apply(G,1,sum),3) }
  G[is.nan(G)] = 0
  assign((matrix_output_name),G,envir=.GlobalEnv)
  return(G)
}
setwd("C:/Users/lambotte/Dropbox/Postdoc Mathieu/R")
G<-file_import("network_baseline_final2_long.xlsx",convert=FALSE,weighted_adjacency=FALSE,row_normalization=TRUE,directed=TRUE)
load("C:/Users/lambotte/Dropbox/Postdoc Mathieu/R/Model dummy avec intercept.RData")
data<-model[[2]]
data<-data[,c(1:14,42:50,52)]
Y_var=colnames(data)[1]
X_var=colnames(data[,c(2:14)])
starting_values=coef(model[[1]])[c(2:14,29:37,15:27,28,1)]
discrete_variables=colnames(data)[c(3,8,9,10,11,13)+1]

#Load or simulate data for external user
data<-data #load a dataframe [Y,X,FE,network] from previous work or simulate one, network is a column indicating in which network each observation belongs, if you have 10 network, you have 9 FE 
#if you only have a dataframe [Y,X,network], you can run this line to create m-1 networks' dummies :
#data<-model.matrix( ~ as.factor(data$Lab) - 1) #where Lab is whatever name given to your column with networks' identifications


#### Simulated Iterative Maximum Likelihood from Lee Li Lin 2014 ####
SIML_LLL<-function(data=data,Y_var="yname",X_var=c("X1","X2"),adjacency_matrix=G,network_var="Lab",starting_values=matrix(0,nrow=(ncol(data)+length(X_var)+1),ncol=1),rep_group=6,discrete_variables=c("X2")){ #data should be [Y, X, Fixed Effects], G sould be a nxn matrix, 
#network_split should be a list of m vector, where m is the number of different networks, and in each list the vector is the row corresponding in the adjacency matrix
#starting_values is a vector of ncol(data)+k+1 ([X,FE,GX,GY,Intercept]) starting values for the estimated coefficients 
#rep_group is the selected group among the m network for the marginal effects estimation 
  #discrete_variables should be a vector of columns names which are discrete variables, coded as 0-1 dummies
Y<-matrix(data[,Y_var]) #binary outcome variable 0 or 1
X<-as.matrix(sapply(data[,!colnames(data)%in%c(Y_var,network_var)], as.numeric))  #X contains the X and the fixed effects' dummies (here 10 labs, so 9 dummies)
k=ncol(X[,X_var]) # number of Xs
d<-ncol(data)-k-2 #number of dummy (fidex effects per school or labs) columns, zero if model without fixed effects
Mg=Y #create a vector of same size at Y, will be the heterogeneous expectations
G<-adjacency_matrix #adjacency matrix (not a list of subnetworks here)
b1<-starting_values #starting values for the parameters, here extracted from a linear in means model, b1 =[X,FE,GX,GY,Intercept] or following the paper eta=[alpha,fixed effects,theta,gamma,intercept]
labs<-split(as.numeric(rownames(data)), data[,network_var])
Y=2*Y-1 #, transformed into -1 1 following the paper
SSE_b=matrix(0,1000,1) #gathers the SSEs over the iterations
#functions
mr_no_randomC2<-function(b){
  yy=0
  gra=matrix(0,nrow=1,ncol=(k*2+d+2))
  
  for(i in 1:length(labs)){
    Xt<-X[labs[[i]],]
    Yt<-Y[labs[[i]]]
    wt<-G[labs[[i]],labs[[i]]]
    Mgt<-Mg[labs[[i]]]
    
    mr<-length(labs[[i]])
    indp_b1=matrix(0,nrow=mr,1)
    indp_b2=matrix(0,nrow=mr,1)
    gra_g=matrix(0,nrow=mr,ncol=(k*2+d+2))
    bb=Xt%*%b[1:(k+d)]+wt%*%Xt[,c(1:k)]%*%b[(k+d+1):(2*k+d)]+Mgt*b[2*k+d+1]+b[2*k+d+2]*matrix(1,nrow=mr,ncol=1)
    
    indp_b1=indp_b1+ (1/(1+exp(-2*bb)))
    indp_b2=indp_b2+ (1/(1+exp(2*bb)))
    
    
    yy=yy+ ((t(matrix(1,nrow=mr,ncol=1)+Yt)/2)%*%log(indp_b1)+(t(matrix(1,nrow=mr,ncol=1)-Yt)/2)%*%log(indp_b2))
    
    
    temp4=cbind(Xt,wt%*%Xt[,c(1:k)],Mgt,matrix(1,nrow=mr,ncol=1))
    
    gra_g=gra_g+temp4
    
    
    gra1=t(2*(((matrix(1,nrow=mr,ncol=1)+Yt)/2)-indp_b1))%*%gra_g
    gra=gra+gra1
  }  
  gr = t(-gra)
  ff=-yy
  return(ff)
} #function to opimize

flag=1
count=1
#Iterinative MLE
while(flag==1){
  for(i in 1:length(labs)){
    Xt<-X[labs[[i]],]
    Yt<-Y[labs[[i]]]
    wt<-G[labs[[i]],labs[[i]]]
    mr<-length(labs[[i]])
    euclid=1
    x0=matrix(1,mr,1)/2
    endog=matrix(0,mr,1)
    
    while (euclid>0.00001){
      xx_new=tanh(Xt%*%b1[1:(k+d)]+wt%*%Xt[,c(1:k)]%*%b1[(k+d+1):(2*k+d)]+wt%*%x0%*%b1[2*k+d+1]+b1[2*k+d+2]*matrix(1,nrow=mr,ncol=1))
      
      euclid=max(sum((xx_new-x0)*(xx_new-x0)))
      x0=xx_new
    }
    
    endog=xx_new;
    Mgt=wt%*%endog
    Mg[labs[[i]]]<-Mgt #updated expectation of peers' choice
  }
  bnew<-optim(b1,mr_no_randomC2,"BFGS") #ounconstrained optimization
  SSE=t(bnew$par-b1)%*%(bnew$par-b1)#compute the SSE
  if (is.na(SSE)){
    flag=0
  }  else if (SSE<0.0001){
    flag=0
  }  else if (count>1000){
    flag=0
  } else {flag=1}
  
  if (flag==1){
    SSE_b[count]=SSE
    b1=(bnew$par-b1)/(ceiling(count/2))+b1
    count=count+1
  }
}
#S.E
graf=matrix(0,(2*k+d+2),(2*k+d+2)) 

for(i in 1:length(labs)){
  Xt<-X[labs[[i]],]
  Yt<-Y[labs[[i]]]
  wt<-G[labs[[i]],labs[[i]]]
  mr<-length(labs[[i]])
  Mgt<-Mg[labs[[i]]]
  
  
  indp_b1f=matrix(0,nrow=mr,1)
  indp_b2f=matrix(0,nrow=mr,1)
  
  gra_gf=matrix(0,nrow=mr,ncol=(k*2+d+2))
  
  bbf=Xt%*%matrix(bnew$par[1:(k+d)])+wt%*%Xt[,c(1:k)]%*%bnew$par[(k+d+1):(2*k+d)]+Mgt*bnew$par[2*k+d+1]+bnew$par[2*k+d+2]*matrix(1,nrow=mr,ncol=1)
  
  
  indp_b1f=indp_b1f+(1/(1+exp(-2*bbf)))
  temp3=indp_b1f
  
  indp_b2f=indp_b2f+(1/(1+exp(2*bbf)))
  
  deri=4/(exp(2*bbf)+exp(-2*bbf)+2)
  temp1=diag(deri[,1],mr,mr)
  temp2=solve(diag(nrow(Xt))-bnew$par[2*k+d+1]*temp1%*%wt)%*%temp1%*%cbind(Xt,wt%*%Xt[,c(1:k)],Mgt,matrix(1,nrow=mr,ncol=1)) #remember to include the constant term.
  
  temp4=cbind(Xt,wt%*%Xt[,c(1:k)],Mgt,matrix(1,nrow=mr,ncol=1))+bnew$par[2*k+d+1]*wt%*%temp2  # remember to include the constant term.
  
  gra_gf=gra_gf+temp4
  
  graf1=2*diag((matrix(1,nrow=mr,ncol=1)+Yt)/(2-temp3))*gra_gf
  
  graf=graf+t(graf1)%*%graf1 
}


msscore = graf/nrow(X)  
se=sqrt(round(diag(pinv(msscore)/nrow(X)),10))
result=cbind(bnew$par, se, 2*(1-pnorm(abs(bnew$par/se))))


# Marginal effects 
# To study the marginal effect, consider an individual in a specific group. So first, find a group as much representative as possible 
bnew1=bnew
gg<-labs[[rep_group]]
n<-lengths(labs)
X_f = X[gg,]
Mg_f<-Mg[gg,]
mr=nrow(X_f)

W_f= G[gg,gg]


indp_b1f=matrix(0,mr,1)
indp_b2f=matrix(0,mr,1)
deri_f=matrix(0,mr,1)


bbf=X_f%*%matrix(bnew$par[1:(k+d)])+W_f%*%X_f[,c(1:k)]%*%bnew$par[(k+d+1):(2*k+d)]+Mg_f*bnew$par[2*k+d+1]+bnew$par[2*k+d+2]*matrix(1,nrow=mr,ncol=1)


indp_b1f=(1/(1+exp(-2*bbf)))
temp3=indp_b1f
F<-temp3


naivemarg=2*(F*(1-F))%*%t(bnew$par)
naivemargm=rowMeans(t(naivemarg[1:n[[rep_group]],]))*100  #en %


ini_n=matrix(0,n[[rep_group]],k)

X_fa=X_f
for(member in 1:n[[rep_group]]){
  # Marginal effect for the discrete variables, kk are the columns of X which are discrete
  for( kk in which(colnames(X)%in%discrete_variables)){ 
    Mg1=Mg_f
    X_fa[member,kk]=0
    indp_b1f=matrix(0,mr,1)
    indp_b2f=matrix(0,mr,1)
    deri_f=matrix(0,mr,1)
    bbf=X_fa%*%matrix(bnew$par[1:(k+d)])+W_f%*%X_fa[,c(1:k)]%*%bnew$par[(k+d+1):(2*k+d)]+Mg1*bnew$par[2*k+d+1]+bnew$par[2*k+d+2]*matrix(1,nrow=mr,ncol=1)
    indp_b1f=(1/(1+exp(-2*bbf)))
    temp3=indp_b1f
    F_before=temp3
    X_fa[member,kk]=1
    Mg1=Mg_f
    indp_b1f=matrix(0,mr,1)
    indp_b2f=matrix(0,mr,1)
    deri_f=matrix(0,mr,1)
    bbf=X_fa%*%matrix(bnew$par[1:(k+d)])+W_f%*%X_fa[,c(1:k)]%*%bnew$par[(k+d+1):(2*k+d)]+Mg1*bnew$par[2*k+d+1]+bnew$par[2*k+d+2]*matrix(1,nrow=mr,ncol=1)
    indp_b1f=(1/(1+exp(-2*bbf)))
    temp3=indp_b1f
    F_after=temp3
    amarg=F_after-F_before;
    ini_n[member,kk]=amarg[member]
    X_fa=X_f
  } 
}  

ini_n2=ini_n[,c(3,8,9,10,11,13)]
ma1_n=rowMeans(t(ini_n2))*100
naivemargm2=naivemargm
naivemargm2[c(3,8,9,10,11,13)]=ma1_n
naivemargm3<-naivemargm2/100*2 #As Y goes from -1 to 1, need to x2 to get the marginal effect of having all peers doing the outcome instead of having zero peers doing it

export<-cbind(result,naivemargm3)
colnames(export)<-c("Estimate","SE","p.value","Marginal Effect")
out<-list(export,2*bnew$value,bnew$counts,bnew$convergence)
names(out)<-c("summary","LogLikelihood","Iterations","Convergence")
return(out)
}
test<-SIML_LLL(data=data,Y_var=Y_var,X_var=X_var,adjacency_matrix=G,network_var="Lab",starting_values=starting_values,rep_group=6,discrete_variables=discrete_variables)



#### Simulated Iterative Maximum Likelihood without dummies ####
SIML_LLL2<-function(data=data,Y_var="yname",X_var=c("X1","X2"),adjacency_matrix=G,network_var="Lab",starting_values=matrix(0,nrow=(ncol(data)+length(X_var)+1),ncol=1),rep_group=6,discrete_variables=c("X2")){ #data should be [Y, X, Fixed Effects], G sould be a nxn matrix, 
  #network_split should be a list of m vector, where m is the number of different networks, and in each list the vector is the row corresponding in the adjacency matrix
  #starting_values is a vector of ncol(data)+k+1 ([X,FE,GX,GY,Intercept]) starting values for the estimated coefficients 
  #rep_group is the selected group among the m network for the marginal effects estimation 
  #discrete_variables should be a vector of columns names which are discrete variables, coded as 0-1 dummies
  Y<-matrix(data[,Y_var]) #binary outcome variable 0 or 1
  X<-as.matrix(sapply(data[,!colnames(data)%in%c(Y_var,network_var)], as.numeric))  #X contains the X and the fixed effects' dummies (here 10 labs, so 9 dummies)
  k=ncol(X[,X_var]) # number of Xs
  X<-X[,X_var]
  Mg=Y #create a vector of same size at Y, will be the heterogeneous expectations
  G<-adjacency_matrix #adjacency matrix (not a list of subnetworks here)
  b1<-starting_values #starting values for the parameters, here extracted from a linear in means model, b1 =[X,FE,GX,GY,Intercept] or following the paper eta=[alpha,fixed effects,theta,gamma,intercept]
  b1<-c(b1[c(1:k)],b1[c(1:k)],b1[length(b1)-1],b1[length(b1)])
  names(b1)<-c(names(b1)[c(1:k)],paste0("G_",names(b1)[c(1:k)]),names(b1[length(b1)-1]),names(b1[length(b1)]))
  labs<-split(as.numeric(rownames(data)), data[,network_var])
  Y=2*Y-1 #, transformed into -1 1 following the paper
  SSE_b=matrix(0,1000,1) #gathers the SSEs over the iterations
  #functions
  mr_no_randomC2<-function(b){
    yy=0
    gra=matrix(0,nrow=1,ncol=(k*2+2))
    
    for(i in 1:length(labs)){
      Xt<-X[labs[[i]],]
      Yt<-Y[labs[[i]]]
      wt<-G[labs[[i]],labs[[i]]]
      Mgt<-Mg[labs[[i]]]
      
      mr<-length(labs[[i]])
      indp_b1=matrix(0,nrow=mr,1)
      indp_b2=matrix(0,nrow=mr,1)
      gra_g=matrix(0,nrow=mr,ncol=(k*2+2))
      bb=Xt%*%matrix(b[1:k])+wt%*%Xt%*%b[(k+1):(2*k)]+Mgt*b[2*k+1]+b[2*k+2]*matrix(1,nrow=mr,ncol=1)
      
      indp_b1=indp_b1+ (1/(1+exp(-2*bb)))
      indp_b2=indp_b2+ (1/(1+exp(2*bb)))
      
      
      yy=yy+ ((t(matrix(1,nrow=mr,ncol=1)+Yt)/2)%*%log(indp_b1)+(t(matrix(1,nrow=mr,ncol=1)-Yt)/2)%*%log(indp_b2))
      
      
      temp4=cbind(Xt,wt%*%Xt[,c(1:k)],Mgt, matrix(1,nrow=mr,ncol=1))
      
      gra_g=gra_g+temp4
      
      
      gra1=t(2*(((matrix(1,nrow=mr,ncol=1)+Yt)/2)-indp_b1))%*%gra_g
      gra=gra+gra1
    }  
    gr = t(-gra)
    ff=-yy
    return(ff)
  } #function to opimize
  
  flag=1
  count=1
  while(flag==1){
    for(i in 1:length(labs)){
      Xt<-X[labs[[i]],]
      Yt<-Y[labs[[i]]]
      wt<-G[labs[[i]],labs[[i]]]
      mr<-length(labs[[i]])
      euclid=1
      x0=matrix(1,mr,1)/2
      endog=matrix(0,mr,1)
      
      while (euclid>0.00001){
        xx_new=tanh(Xt%*%matrix(b1[1:k])+wt%*%Xt%*%b1[(k+1):(2*k)]+wt%*%x0%*%b1[2*k+1]+b1[2*k+2]*matrix(1,nrow=mr,ncol=1))
        euclid=max(sum((xx_new-x0)*(xx_new-x0)))
        x0=xx_new
      }
      
      endog=xx_new;
      Mgt=wt%*%endog
      Mg[labs[[i]]]<-Mgt
    }
    
    bnew<-optim(b1,mr_no_randomC2,method="BFGS")
    SSE=t(bnew$par-b1)%*%(bnew$par-b1)
    if (is.na(SSE)){
      flag=0
    }  else if (SSE<0.0001){
      flag=0
    }  else if (count>1000){
      flag=0
    } else {flag=1}
    
    if (flag==1){
      SSE_b[count]=SSE
      b1=(bnew$par-b1)/(ceiling (count/2))+b1
      count=count+1
    }
  }
  #S.E
  graf=matrix(0,(2*k+2),(2*k+2)) 
  
  for(i in 1:length(labs)){
    Xt<-X[labs[[i]],]
    Yt<-Y[labs[[i]]]
    wt<-G[labs[[i]],labs[[i]]]
    mr<-length(labs[[i]])
    Mgt<-Mg[labs[[i]]]
    
    
    indp_b1f=matrix(0,nrow=mr,1)
    indp_b2f=matrix(0,nrow=mr,1)
    
    gra_gf=matrix(0,nrow=mr,ncol=(k*2+2))
    
    bbf=Xt%*%matrix(bnew$par[1:k])+wt%*%Xt%*%bnew$par[(k+1):(2*k)]+Mgt*bnew$par[2*k+1]+bnew$par[2*k+2]*matrix(1,nrow=mr,ncol=1)
    indp_b1f=indp_b1f+(1/(1+exp(-2*bbf)))
    temp3=indp_b1f
    
    indp_b2f=indp_b2f+(1/(1+exp(2*bbf)))
    
    deri=4/(exp(2*bbf)+exp(-2*bbf)+2)
    temp1=diag(deri[,1],mr,mr)
    temp2=solve(diag(nrow(Xt))-bnew$par[2*k+1]*temp1%*%wt)%*%temp1%*%cbind(Xt,wt%*%Xt,Mgt, matrix(1,nrow=mr,ncol=1)) #remember to include the constant term.
    
    temp4=cbind(Xt,wt%*%Xt,Mgt, matrix(1,nrow=mr,ncol=1))+bnew$par[2*k+1]*wt%*%temp2  # remember to include the constant term.
    
    gra_gf=gra_gf+temp4
    
    graf1=2*diag((matrix(1,nrow=mr,ncol=1)+Yt)/(2-temp3))*gra_gf
    
    graf=graf+t(graf1)%*%graf1 
  }
  
  msscore = graf/nrow(X)  
  se=sqrt(round(diag(pinv(msscore)/nrow(X)),10))
  result=cbind(bnew$par, se, 2*(1-pnorm(abs(bnew$par/se))))
  
  
  # Marginal effects 
  # To study the marginal effect, consider an individual in a specific group. So first, find a group as much representative as possible 
  bnew1=bnew
  gg<-labs[[rep_group]]
  n<-lengths(labs)
  X_f = X[gg,]
  Mg_f<-Mg[gg,]
  mr=nrow(X_f)
  
  W_f= G[gg,gg]
  
  
  indp_b1f=matrix(0,mr,1)
  indp_b2f=matrix(0,mr,1)
  deri_f=matrix(0,mr,1)
  
  
  bbf=X_f%*%matrix(bnew$par[1:k])+W_f%*%X_f[,c(1:k)]%*%bnew$par[(k+1):(2*k)]+Mg_f*bnew$par[2*k+1]+bnew$par[2*k+2]*matrix(1,nrow=mr,ncol=1)
  
  
  indp_b1f=(1/(1+exp(-2*bbf)))
  temp3=indp_b1f
  F<-temp3
  
  
  naivemarg=2*(F*(1-F))%*%t(bnew$par)
  naivemargm=rowMeans(t(naivemarg[1:n[[rep_group]],]))*100  #en %
  
  
  ini_n=matrix(0,n[[rep_group]],k)
  
  X_fa=X_f
  for(member in 1:n[[rep_group]]){
    # Marginal effect for the discrete variables, kk are the columns of X which are discrete
    for( kk in which(colnames(X)%in%discrete_variables)){ 
      Mg1=Mg_f
      X_fa[member,kk]=0
      indp_b1f=matrix(0,mr,1)
      indp_b2f=matrix(0,mr,1)
      deri_f=matrix(0,mr,1)
      bbf=X_fa%*%matrix(bnew$par[1:(k)])+W_f%*%X_fa[,c(1:k)]%*%bnew$par[(k+1):(2*k)]+Mg1*bnew$par[2*k+1]+bnew$par[2*k+2]*matrix(1,nrow=mr,ncol=1)
      indp_b1f=(1/(1+exp(-2*bbf)))
      temp3=indp_b1f
      F_before=temp3
      X_fa[member,kk]=1
      Mg1=Mg_f
      indp_b1f=matrix(0,mr,1)
      indp_b2f=matrix(0,mr,1)
      deri_f=matrix(0,mr,1)
      bbf=X_fa%*%matrix(bnew$par[1:(k)])+W_f%*%X_fa[,c(1:k)]%*%bnew$par[(k+1):(2*k)]+Mg1*bnew$par[2*k+1]+bnew$par[2*k+2]*matrix(1,nrow=mr,ncol=1)
      indp_b1f=(1/(1+exp(-2*bbf)))
      temp3=indp_b1f
      F_after=temp3
      amarg=F_after-F_before;
      ini_n[member,kk]=amarg[member]
      X_fa=X_f
    } 
  }  
  
  ini_n2=ini_n[,c(3,8,9,10,11,13)]
  ma1_n=rowMeans(t(ini_n2))*100
  naivemargm2=naivemargm
  naivemargm2[c(3,8,9,10,11,13)]=ma1_n
  naivemargm3<-naivemargm2/100*2 #As Y goes from -1 to 1, need to x2 to get the marginal effect of having all peers doing the outcome instead of having zero peers doing it
  
  export<-cbind(result,naivemargm3)
  colnames(export)<-c("Estimate","SE","p.value","Marginal Effect")
  out<-list(export,2*bnew$value,bnew$counts,bnew$convergence)
  names(out)<-c("summary","LogLikelihood","Iterations","Convergence")
  return(out)
}
test<-SIML_LLL2(data=data,Y_var=Y_var,X_var=X_var,adjacency_matrix=G,network_var="Lab",starting_values=starting_values,rep_group=6,discrete_variables=discrete_variables)


#### Simulated Iterative Maximum Likelihood endogenous effect only ####
SIML_LLL3<-function(data=data,Y_var="yname",X_var=c("X1","X2"),adjacency_matrix=G,network_var="Lab",starting_values=matrix(0,nrow=(ncol(data)+length(X_var)+1),ncol=1),rep_group=6,discrete_variables=c("X2")){ #data should be [Y, X, Fixed Effects], G sould be a nxn matrix, 
  #network_split should be a list of m vector, where m is the number of different networks, and in each list the vector is the row corresponding in the adjacency matrix
  #starting_values is a vector of ncol(data)+k+1 ([X,FE,GX,GY,Intercept]) starting values for the estimated coefficients 
  #rep_group is the selected group among the m network for the marginal effects estimation 
  #discrete_variables should be a vector of columns names which are discrete variables, coded as 0-1 dummies
  Y<-matrix(data[,Y_var]) #binary outcome variable 0 or 1
  X<-as.matrix(sapply(data[,!colnames(data)%in%c(Y_var,network_var)], as.numeric))  #X contains the X and the fixed effects' dummies (here 10 labs, so 9 dummies)
  k=ncol(X[,X_var]) # number of Xs
  X<-X[,X_var]

  G<-adjacency_matrix #adjacency matrix (not a list of subnetworks here)
  b1<-starting_values #starting values for the parameters, here extracted from a linear in means model, b1 =[X,FE,GX,GY,Intercept] or following the paper eta=[alpha,fixed effects,theta,gamma,intercept]
  b1<-c(b1[c(1:k)],b1[length(b1)-1],b1[length(b1)])
  names(b1)<-c(names(b1)[c(1:k)],names(b1[length(b1)-1]),names(b1[length(b1)]))
  labs<-split(as.numeric(rownames(data)), data[,network_var])
    Mg=Y #create a vector of same size at Y, will be the heterogeneous expectations
  Y=2*Y-1 #, transformed into -1 1 following the paper
  SSE_b=matrix(0,1000,1) #gathers the SSEs over the iterations
  #functions
  mr_no_randomC2<-function(b){
    yy=0
    gra=matrix(0,nrow=1,ncol=(k+2))
    
    for(i in 1:length(labs)){
      Xt<-X[labs[[i]],]
      Yt<-Y[labs[[i]]]
      wt<-G[labs[[i]],labs[[i]]]
      Mgt<-Mg[labs[[i]]]
      
      mr<-length(labs[[i]])
      indp_b1=matrix(0,nrow=mr,1)
      indp_b2=matrix(0,nrow=mr,1)
      gra_g=matrix(0,nrow=mr,ncol=(k+2))
      bb=Xt%*%matrix(b[1:k])+Mgt*b[k+1]+b[k+2]*matrix(1,nrow=mr,ncol=1)
      
      indp_b1=indp_b1+ (1/(1+exp(-2*bb)))
      indp_b2=indp_b2+ (1/(1+exp(2*bb)))
      
      
      yy=yy+ ((t(matrix(1,nrow=mr,ncol=1)+Yt)/2)%*%log(indp_b1)+(t(matrix(1,nrow=mr,ncol=1)-Yt)/2)%*%log(indp_b2))
      
      
      temp4=cbind(Xt,Mgt, matrix(1,nrow=mr,ncol=1))
      
      gra_g=gra_g+temp4
      
      
      gra1=t(2*(((matrix(1,nrow=mr,ncol=1)+Yt)/2)-indp_b1))%*%gra_g
      gra=gra+gra1
    }  
    gr = t(-gra)
    ff=-yy
    return(ff)
  } #function to opimize
  
  flag=1
  count=1
  while(flag==1){
    for(i in 1:length(labs)){
      Xt<-X[labs[[i]],]
      Yt<-Y[labs[[i]]]
      wt<-G[labs[[i]],labs[[i]]]
      mr<-length(labs[[i]])
      euclid=1
      x0=matrix(1,mr,1)/2
      endog=matrix(0,mr,1)
      
      while (euclid>0.00001){
        xx_new=tanh(Xt%*%matrix(b1[1:k])+wt%*%x0%*%b1[k+1]+b1[k+2]*matrix(1,nrow=mr,ncol=1))
        euclid=max(sum((xx_new-x0)*(xx_new-x0)))
        x0=xx_new
      }
      
      endog=xx_new;
      Mgt=wt%*%endog
      Mg[labs[[i]]]<-Mgt
    }
    
    bnew<-optim(b1,mr_no_randomC2,method="BFGS")
    SSE=t(bnew$par-b1)%*%(bnew$par-b1)
    if (is.na(SSE)){
      flag=0
    }  else if (SSE<0.0001){
      flag=0
    }  else if (count>1000){
      flag=0
    } else {flag=1}
    
    if (flag==1){
      SSE_b[count]=SSE
      b1=(bnew$par-b1)/(ceiling (count/2))+b1
      count=count+1
    }
  }
  #S.E
  graf=matrix(0,(k+2),(k+2)) 
  
  for(i in 1:length(labs)){
    Xt<-X[labs[[i]],]
    Yt<-Y[labs[[i]]]
    wt<-G[labs[[i]],labs[[i]]]
    mr<-length(labs[[i]])
    Mgt<-Mg[labs[[i]]]
    
    
    indp_b1f=matrix(0,nrow=mr,1)
    indp_b2f=matrix(0,nrow=mr,1)
    
    gra_gf=matrix(0,nrow=mr,ncol=(k+2))
    
    bbf=Xt%*%matrix(bnew$par[1:k])+Mgt*bnew$par[k+1]+bnew$par[k+2]*matrix(1,nrow=mr,ncol=1)
    indp_b1f=indp_b1f+(1/(1+exp(-2*bbf)))
    temp3=indp_b1f
    
    indp_b2f=indp_b2f+(1/(1+exp(2*bbf)))
    
    deri=4/(exp(2*bbf)+exp(-2*bbf)+2)
    temp1=diag(deri[,1],mr,mr)
    temp2=solve(diag(nrow(Xt))-bnew$par[k+1]*temp1%*%wt)%*%temp1%*%cbind(Xt,Mgt, matrix(1,nrow=mr,ncol=1)) #remember to include the constant term.
    
    temp4=cbind(Xt,Mgt, matrix(1,nrow=mr,ncol=1))+bnew$par[k+1]*wt%*%temp2  # remember to include the constant term.
    
    gra_gf=gra_gf+temp4
    
    graf1=2*diag((matrix(1,nrow=mr,ncol=1)+Yt)/(2-temp3))*gra_gf
    
    graf=graf+t(graf1)%*%graf1 
  }
  
  msscore = graf/nrow(X)  
  se=sqrt(round(diag(pinv(msscore)/nrow(X)),10))
  result=cbind(bnew$par, se, 2*(1-pnorm(abs(bnew$par/se))))
  
  
  # Marginal effects 
  # To study the marginal effect, consider an individual in a specific group. So first, find a group as much representative as possible 
  bnew1=bnew
  gg<-labs[[rep_group]]
  n<-lengths(labs)
  X_f = X[gg,]
  Mg_f<-Mg[gg,]
  mr=nrow(X_f)
  
  W_f= G[gg,gg]
  
  
  indp_b1f=matrix(0,mr,1)
  indp_b2f=matrix(0,mr,1)
  deri_f=matrix(0,mr,1)
  
  
  bbf=X_f%*%matrix(bnew$par[1:k])+Mg_f*bnew$par[k+1]+bnew$par[k+2]*matrix(1,nrow=mr,ncol=1)
  
  
  indp_b1f=(1/(1+exp(-2*bbf)))
  temp3=indp_b1f
  F<-temp3
  
  
  naivemarg=2*(F*(1-F))%*%t(bnew$par)
  naivemargm=rowMeans(t(naivemarg[1:n[[rep_group]],]))*100  #en %
  
  
  ini_n=matrix(0,n[[rep_group]],k)
  
  X_fa=X_f
  for(member in 1:n[[rep_group]]){
    # Marginal effect for the discrete variables, kk are the columns of X which are discrete
    for( kk in which(colnames(X)%in%discrete_variables)){ 
      Mg1=Mg_f
      X_fa[member,kk]=0
      indp_b1f=matrix(0,mr,1)
      indp_b2f=matrix(0,mr,1)
      deri_f=matrix(0,mr,1)
      bbf=X_fa%*%matrix(bnew$par[1:k])+Mg1*bnew$par[k+1]+bnew$par[k+2]*matrix(1,nrow=mr,ncol=1)
      indp_b1f=(1/(1+exp(-2*bbf)))
      temp3=indp_b1f
      F_before=temp3
      X_fa[member,kk]=1
      Mg1=Mg_f
      indp_b1f=matrix(0,mr,1)
      indp_b2f=matrix(0,mr,1)
      deri_f=matrix(0,mr,1)
      bbf=X_fa%*%matrix(bnew$par[1:(k)])+Mg1*bnew$par[k+1]+bnew$par[k+2]*matrix(1,nrow=mr,ncol=1)
      indp_b1f=(1/(1+exp(-2*bbf)))
      temp3=indp_b1f
      F_after=temp3
      amarg=F_after-F_before;
      ini_n[member,kk]=amarg[member]
      X_fa=X_f
    } 
  }  
  
  ini_n2=ini_n[,c(3,8,9,10,11,13)]
  ma1_n=rowMeans(t(ini_n2))*100
  naivemargm2=naivemargm
  naivemargm2[c(3,8,9,10,11,13)]=ma1_n
  naivemargm3<-naivemargm2/100*2 #As Y goes from -1 to 1, need to x2 to get the marginal effect of having all peers doing the outcome instead of having zero peers doing it
  
  export<-cbind(result,naivemargm3)
  colnames(export)<-c("Estimate","SE","p.value","Marginal Effect")
  out<-list(export,2*bnew$value,bnew$counts,bnew$convergence)
  names(out)<-c("summary","LogLikelihood","Iterations","Convergence")
  return(out)
}
test<-SIML_LLL3(data=data,Y_var=Y_var,X_var=X_var,adjacency_matrix=G,network_var="Lab",starting_values=starting_values,rep_group=6,discrete_variables=discrete_variables)


#### Non linear least squares from Boucher & Bramoullé 2020 ####
NLS_BB<-function(data=data,Y_var=Y_var,X_var=X_var,dummy=TRUE,exogenous_effect=TRUE,adjacency_matrix=G,network_var="Lab",staring_value=0.5){ #starting_value for the endogenous peer effect, size_min is the minimal size for networks
 Y<-matrix(data[,Y_var]) #binary outcome variable 0 or 1
X<-as.matrix(sapply(data[,!colnames(data)%in%c(Y_var,network_var)], as.numeric))  #X contains the X and the fixed effects' dummies (here 10 labs, so 9 dummies)
k=ncol(X[,X_var]) # number of Xs
if(dummy==TRUE){
  d<-ncol(data)-k-2 #number of dummy (fixed effects per school or labs) columns, zero if model without fixed effects
} else {d=0}
if(exogenous_effect==TRUE){
 GX<-G%*%X[,c(1:k)] #number of dummy (fixed effects per school or labs) columns, zero if model without fixed effects
colnames(GX)<-paste0("G_",colnames(X[,c(1:k)]))
 } else {GX=NULL}

G<-adjacency_matrix #adjacency matrix (not a list of subnetworks here)
labs<-split(as.numeric(rownames(data)), data[,network_var])
n<-lengths(labs)
m<-length(labs)
nlscon <- function(b){
  ## sub-function for the (concentrated NLS)
  ## computes the objective function for a specific value of beta
  
  out <- 0 # initialize objective
  Z <- vector("list", m) # initialize list
  for (i in 1:m){ # for each group
    nt <- n[i] # number of students in group i
    Z[[i]] <- solve(diag(nt)-b*G[labs[[i]],labs[[i]]])%*%cbind(matrix(1,nt,1),X[labs[[i]],c(1:(k+9))],GX[labs[[i]],]) # probability of y=1 in group i
  }
  LZ <- do.call(rbind,Z) # bind all probabilities
  LY <- Y # bind all observed choices
  
  # computes the objective function
  int <- solve(t(LZ)%*%LZ)
  ext <- t(LZ)%*%LY
  out <- t(ext)%*%int%*%ext
  return(-out)
}

nls <- function(start){
  # NLS routine, returns the estimated parameters
  b <- optim(start,nlscon, method='BFGS')$par # optimize the concentrated NLS
  nt <- n[1] # size of the first group
  bZ <- solve(diag(nt)-b*G[labs[[1]],labs[[1]]])%*%cbind(matrix(1,nt,1),X[labs[[1]],c(1:(k+d))],GX[labs[[1]],]) # probability of y=1 for the first group
  bY <- matrix(Y[labs[[1]]],nrow=nt,ncol=1) # y for the first group
  for (i in 2:m){ # for each groups>1
    nt <- n[i] # size of group i
    Z <- solve(diag(nt)-b*G[labs[[i]],labs[[i]]])%*%cbind(matrix(1,nt,1),X[labs[[i]],c(1:(k+d))],GX[labs[[i]],]) # probability of y=1 for group i
    bZ <- rbind(bZ,Z) # bind with the probabilities of the other groups
    bY <- rbind(bY,matrix(Y[labs[[i]]],nrow=nt,ncol=1)) # bind with the y of the other groups
  }
  par <- solve(t(bZ)%*%bZ)%*%t(bZ)%*%bY # OLS (conditional on b)
  coefs<-c(par,b)
  if(dummy==TRUE){
    names(coefs)<-c("Intercept",X_var,colnames(X[,!colnames(X)%in%X_var]),colnames(GX),paste0("G_",Y_var))
  } else {names(coefs)<-c("Intercept",X_var,colnames(GX),paste0("G_",Y_var))}
  
  return(coefs) # return the parameters
}

nlsSE <- function(para){
  # computes the variance-covariance matrix for the NLS
  siz <- sum(n) # total number of individuals
  grad <- matrix(0,siz,length(para)) # initialize
  res <- matrix(0,siz,1) # initialize residuals
  mpara <- matrix(para[1:(length(para)-1)],(length(para)-1),1) # parameter values as matrix
  for (i in 1:m){ # for each group i
    nt <- n[i] # size of group i
    #position of the first individual in group i
    if (i==1){
      p1 <-1
    } else{
      p1 <- sum(n[1:(i-1)])+1
    }
    p2 <- p1+n[i]-1 # position of the last individual in group i
    Minv <- solve(diag(nt)-para[length(para)]*G[labs[[i]],labs[[i]]]) # computes the inverse (I-betaG)^(-1)
    bZ <- Minv%*%cbind(matrix(1,nt,1),X[labs[[i]],c(1:(k+d))],GX[labs[[i]],]) # computes the probability of y=1
    grad[p1:p2,1:(length(para)-1)] <- bZ # computes for alpha,gamma,delta
    grad[p1:p2,length(para)] <- Minv%*%G[labs[[i]],labs[[i]]]%*%bZ%*%mpara # computes for beta
    bY <- matrix(Y[labs[[i]]],nrow=nt,ncol=1) # get y for group i
    res[p1:p2,1] <- (bY - bZ%*%mpara)^2 # computes the squared residuals
  }
  #computes the robust variance covariance matrix
  DpD <- solve(t(grad)%*%grad)
  grad2 <- t(grad)
  for (i in 1:siz){
    grad2[,i] <- grad2[,i]*res[i,1]
  }
  se <- DpD%*%grad2%*%grad%*%DpD
  return(se)
}

predictprob <- function(para){
  # computes the variance-covariance matrix for the NLS
  siz <- sum(n) # total number of individuals
  grad <- matrix(0,siz,1) # initialize
  mpara <- matrix(para[1:(length(para)-1)],(length(para)-1),1) # parameter values as matrix
  
  for (i in 1:m){ # for each group i
    nt <- n[i] # size of group i
    #position of the first individual in group i
    if (i==1){
      p1 <-1
    } else{
      p1 <- sum(n[1:(i-1)])+1
    }
    p2 <- p1+n[i]-1 # position of the last individual in group i
    Minv <- solve(diag(nt)-para[length(para)]*G[labs[[i]],labs[[i]]]) # computes the inverse (I-betaG)^(-1)
      bZ <- Minv%*%cbind(matrix(1,nt,1),X[labs[[i]],c(1:(k+d))],GX[labs[[i]],]) # computes the probability of y=1
    grad[p1:p2,1] <- bZ%*%mpara # computes predicted proba
  }
  return(c(grad))
}

nlsestimate <- nls(start=staring_value)
nlsVC <- nlsSE(nlsestimate)
SE<-sqrt(diag(nlsVC))
t<-nlsestimate/SE
df<-sum(n)-length(nlsestimate)
pvalue<-pt(t,df=df,lower.tail = FALSE)
fitval <- predictprob(nlsestimate)
okfit2 <- sum(as.numeric((fitval>=0)&(fitval<=1)))/sum(n)*100
export<-list(data.frame(nlsestimate,SE,t,pvalue),okfit2)
names(export)<-c("summary","Correct Predictions")
return(export)
}
test<-NLS_BB(data=data,Y_var=Y_var,X_var=X_var,dummy=TRUE,exogenous_effect=TRUE,adjacency_matrix=G,network_var="Lab",staring_value=0.5)



#### 2SLS from Boucher & Bramoullé 2020 - Main function so more options ####
IV_BB<-function(data=data,Y_var=Y_var,X_var=X_var,adjacency_matrix=G,network_var="Lab",get.df=FALSE,fixed_effect=TRUE,dummy=FALSE,
                exogenous_effect=FALSE,clustered=TRUE){
  
Y<-matrix(data[,Y_var]) #binary outcome variable 0 or 1
X<-as.matrix(sapply(data[,!colnames(data)%in%c(Y_var,network_var)], as.numeric))  #X contains the X and the fixed effects' dummies (here 10 labs, so 9 dummies)
k=ncol(X[,X_var]) # number of Xs
d<-ncol(data)-k-2 #number of dummy (fidex effects per school or labs) columns, zero if model without fixed effects
G<-adjacency_matrix #adjacency matrix (not a list of subnetworks here)
labs<-split(as.numeric(rownames(data)), data[,network_var])  
m <- length(labs) # number of labs
n<-lengths(labs)  #individuals per labs
if(size_min>0){
  siz <- 334 # total number of individuals
}else {siz=sum(n)}

#Creating empty matrices for the transformed matrices
bX <- matrix(1,siz,(2*k+1)) # regressors are  X + GX + gy
bZ <- matrix(1,siz,k) # instruments are G^2X
bY <- matrix(1,siz,1) # explained var is Y
clust <- matrix(1,siz,1) # group number
dummies<-matrix(0,siz,d+1)

#Filling the matrices with the transformation for fixed effects, binded in "df", our final dataset
#final dataset is [Y,X,GX,GY,G2X,lab name]
for (i in 1:m){ # for each group
  
  Yt <- Y[labs[[i]],] # get Y for group "labs"
  Xt <- as.matrix(X[labs[[i]],c(1:k)]) # get X for group "labs"
  Gt <- G[labs[[i]],labs[[i]]] # get G for group "labs"
  
  nt <- nrow(Xt) # get the number of members in group "labs"
  if(fixed_effect==TRUE){
    Jt <- diag(nt) -matrix((1/nt),nt,nt) #Jt captures the deviation from the lab's mean, J= I-H, where H is a nxn matrix with value 1/n everywhere  (Bramoullé 2009, global transformation p48 & Boucher & Bramoullé 2020 top of p17)
  }
  if(fixed_effect==FALSE){
    Jt <- diag(nt) 
  } 
  bX[labs[[i]],] <- cbind(Jt%*%Xt,Jt%*%Gt%*%Xt,Jt%*%Gt%*%Yt) # explanatory variables  X + GX + GY (in deviation with group average)
  bZ[labs[[i]],] <- Jt%*%Gt%*%Gt%*%Xt # instruments (in deviation with group average)
  bY[labs[[i]],1] <- Jt%*%(Yt) # outcome variable (in deviation with group average)
  clust[labs[[i]],1] <- names(labs)[i] # group number
  dummies[labs[[i]],i]<-1
  df<-data.frame(cbind(bY,bX,bZ,dummies,clust)) # returns the dataset
  colnames(df)<-c(paste0(Y_var),paste0(colnames(X[,c(1:k)])),paste0("G_", colnames(X[,c(1:k)])),paste0("G_",Y_var),
                  paste0("G2_", colnames(X[,c(1:k)])),paste0("D_",names(labs)),"Lab")
  df<-df%>%mutate_at(vars(-Lab),as.numeric)%>%mutate(Lab=as.factor(Lab))
  }  


if(exogenous_effect==TRUE){
if(fixed_effect==TRUE){
formula<-as.formula(paste(paste0(Y_var), paste("~",paste("0+",paste(paste0(colnames(X[,X_var]),sep="",collapse = "+"),paste0(paste0("G_",colnames(X[,X_var])),sep="",collapse = "+"),
paste0("G_",Y_var),sep="+")),"|","0+",paste(paste0(colnames(X[,X_var]),sep="",collapse = "+"),paste0(paste0("G_",colnames(X[,X_var])),sep="",collapse = "+"),
paste0(paste0("G2_",colnames(X[,X_var])),sep="",collapse = "+"),sep="+"))))
}
if(fixed_effect==FALSE&dummy==FALSE){
formula<-as.formula(paste(paste0(colnames(Y_var)), paste("~",paste(paste(paste0(colnames(X[,X_var]),sep="",collapse = "+"),paste0(paste0("G_",colnames(X[,X_var])),sep="",collapse = "+"),
paste0("G_",(Y_var)),sep="+")),"|",paste(paste0(colnames(X[,X_var]),sep="",collapse = "+"),paste0(paste0("G_",colnames(X[,X_var])),sep="",collapse = "+"),
paste0(paste0("G2_",colnames(X[,X_var])),sep="",collapse = "+"),sep="+"))))
}
if(fixed_effect==FALSE&dummy==TRUE){
formula<-as.formula(paste(paste0(colnames(Y_var)), paste("~",paste("1+",paste(paste0(colnames(X[,X_var]),sep="",collapse = "+"),paste0(paste0("G_",colnames(X[,X_var])),sep="",collapse = "+"),
paste0("G_",(Y_var)),paste0("D_",names(labs)[paste0("D_",names(labs))%in%colnames(data[,c((1+k+1):(ncol(data)-1))])],sep="",collapse = "+"),sep="+")),"|","1+",paste(paste0(colnames(X[,X_var]),sep="",collapse = "+"),paste0(paste0("G_",colnames(X[,X_var])),sep="",collapse = "+"),
paste0(paste0("G2_",colnames(X[,X_var])),sep="",collapse = "+"),paste0("D_",names(labs)[paste0("D_",names(labs))%in%colnames(data[,c((1+k+1):(ncol(data)-1))])],sep="",collapse = "+"),sep="+"))))
}
}


if(exogenous_effect==FALSE){
if(fixed_effect==TRUE){
formula<-as.formula(paste(paste0((Y_var)), paste("~",paste("0+",paste(paste0(colnames(X[,X_var]),sep="",collapse = "+"),paste0("G_",(Y_var)),sep="+")),
"|","0+",paste(paste0(colnames(X[,X_var]),sep="",collapse = "+"),paste0(paste0("G2_",colnames(X[,X_var])),sep="",collapse = "+"),sep="+"))))
}
if(fixed_effect==FALSE&dummy==FALSE){
formula<-as.formula(paste(paste0((Y_var)), paste("~",paste(paste(paste0(colnames(X[,X_var]),sep="",collapse = "+"),
paste0("G_",(Y_var)),sep="+")),"|",paste(paste0(colnames(X[,X_var]),sep="",collapse = "+"), paste0(paste0("G2_",colnames(X[,X_var])),sep="",collapse = "+"),sep="+"))))
}
if(fixed_effect==FALSE&dummy==TRUE){
formula<-as.formula(paste(paste0((Y_var)), paste("~",paste("1+",paste(paste0(colnames(X[,X_var]),sep="",collapse = "+"),paste0("G_",(Y_var)),
 paste0("D_",names(labs)[paste0("D_",names(labs))%in%colnames(data[,c((1+k+1):(ncol(data)-1))])],sep="",collapse = "+"),sep="+")),"|","1+",paste(paste0(colnames(X[,X_var]),sep="",collapse = "+"), paste0(paste0("G2_",colnames(X[,X_var])),sep="",collapse = "+"),
  paste0("D_",names(labs)[paste0("D_",names(labs))%in%colnames(data[,c((1+k+1):(ncol(data)-1))])],sep="",collapse = "+"),sep="+"))))
}
}

if(clustered==TRUE){
  model_iv<-iv_robust(formula,data=df,clusters=clust,diagnostics = TRUE) 
}
if(clustered==FALSE){
  model_iv<-iv_robust(formula,data=df,diagnostics = TRUE)
}

if(get.df==TRUE){
  return(list(model_iv,df))
}
if(get.df==FALSE){
  return(model_iv)
}
}
test<-IV_BB(data=data,Y_var=Y_var,X_var=X_var,adjacency_matrix=G,network_var="Lab",get.df=FALSE,fixed_effect=TRUE,dummy=FALSE,
            exogenous_effect=FALSE,clustered=TRUE)
