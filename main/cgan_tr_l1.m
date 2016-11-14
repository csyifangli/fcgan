function [x, as, hist, iter] = cgan_tr_l1(y,param)
% for simultaneously low rank and sparse matrix estimation
% usage [x, as, hist, iter] = cgan_lgl(y,param)
%
% FUNCTION PERFORMS A MINIMIZATION OF THE FORM:
% min_x 0.5|| y - x ||^2  + lambda * ||x||_1 + mu *  ||x||_tr
%
%
%
% INPUTS:
% y            = observation matrix
% param.lambda = regularization parameter for l1 norm
% param.mu     = regularization parameter for trace norm
%
% OPTIONAL INPUTS
% param.max_nb_iter    = default 500 = maximum number of iterations allowed default = 500;
% param.max_nb_atoms   = default 500 = maximum number of atoms (used to allocate memory)
% param.epsStop        = default 1e-5 = tolerance parameter
% param.debug          = false = to debug;
% param.debug_asqp     = false = to debug inside asqp
%
% OUTPUTS :
% x           = final result
% as.atoms    = final atomic set
% as.coeffs   = final coefficients
% hist.obj    = objective function value
% hist.dg     = duality gap
% hist.loss   = loss  value
% hist.pen    = penality value
% hist.tt     = time taken since start of the iterations
% iter        = nb of iterations in total (for column generation, the nb of calls to active-set)
%
%%%%%%%%%%%%
% Marina Vinyes and Guillaume Obozinski, 2016
% %%%%%%%%%%%%


param_bcmm.debug_mode= false;
param_bcmm.rho= 0.5;
param_bcmm.max_iter= 50;
param_bcmm.lambda= param.lambda;
param_bcmm.mu= param.mu;

param_as.epsilon= 1e-10;
param_as.ws=param.ws;
if param.ws
    param_as.max_iter= 1000;
else
    param_as.max_iter= 100;
end


[n,m]=size(y);
nm=n*m; % dimension for the vectorized matrix
y=y(:);
x=zeros(nm,1);
keyboard;


max_nb_atoms=param.max_nb_atoms;
max_nb_iter=param.max_nb_iter;
lambda=param.lambda;
mu=param.mu;

as.atoms=sparse([],[],[],nm,max_nb_atoms,max_nb_atoms*nm);
H=sparse([],[],[],max_nb_atoms,max_nb_atoms,max_nb_atoms*max_nb_atoms);
as.coeffs=[];

if param.debug
    maxvals=[];
end

dg=zeros(max_nb_iter,1);
obj=zeros(max_nb_iter,1);
loss=zeros(max_nb_iter,1);
pen=zeros(max_nb_iter,1);
tt=zeros(max_nb_iter,1);
nb_pivot=zeros(max_nb_iter,1);
active_var=zeros(max_nb_iter,1);

npiv=0;
max_atom_count_reached=0;
iter=0;
atom_count=0;

tic

while(iter<max_nb_iter),
    if iter>0,
        if atom_count==0,
            error('all atoms have been thrown away');
        end
        if new_atom_added,
            coeffs_ws=[as.coeffs;0];
        else
            coeffs_ws=as.coeffs;
        end
        switch param.method,
            case 'asqp'
                % call bcmm, output x, d and the dual variable gamma 
                [coeffs, x, gamma, niter]=bcmm_tr_l1(coeffs_ws, x_ws, gamm_ws, param_bcmm, param);
                % Hard threshold small negative values
                smallValues=find(coeffs<0); % for numerical issues
                coeffs(smallValues)=zeros(length(smallValues),1);
                %manage H and the set of atoms
                Jset=smallValues;
                atom_count=sum(Jset);
                H=H(Jset,Jset);
                as.atoms(:,1:atom_count)=as.atoms(:,Jset);
                as.atoms(:,(atom_count+1):end)=0;
                coeffs=coeffs(Jset,1);
            otherwise
                error('Unknown method');
        end
        
        %% Compute the current solution
        as.coeffs=sparse(coeffs);
        x=as.atoms(:,1:atom_count)*as.coeffs;
    end
    
    iter=iter+1;
    
    %% Compute gradient
    g=x-y;    
    
    
    %% Compute objective, loss and penalty
    
    tau=sum(as.coeffs);
    loss(iter)=0.5*sum(g.^2);
    
    pen(iter)=lambda*tau;
    obj(iter)=loss(iter)+pen(iter);
    
    if iter>1,
        if obj(iter)>obj(iter-1)
        end
    end
    
    %%  Store nb of pivot and nb of active variables
    
    if strcmp(param.method,'asqp')
        nb_pivot(iter)=npiv;
        active_var(iter)=sum(as.coeffs>0);
    end
    
    %% Get new atom
    
    [maxval,new_atom]=feval(param.lmo,-g,param);
    
    if maxval>lambda,
        A=1:atom_count;
        atom_count=atom_count+1;
        max_atom_count_reached=max(max_atom_count_reached,atom_count);
        % Inserting the new atom
        as.atoms(:,atom_count)=new_atom;
        
        if full(new_atom)'*g>0,
            error('new atom wrong');
        end
        new_atom_added=true;
    else
        new_atom_added=false;
        switch param.method,
            case 'asqp',
                error('In ASQP an atom should be added at each step. Debug needed');
            otherwise
                %disp('Forward step towards origin');
        end
    end
    
    if atom_count>max_nb_atoms,
        error('max number of atoms reached. Either atom storage is too small or atom dropping is not working correctly');
    end
    
    
    %% Compute duality gap
    
    c=min(1,lambda./maxval);
    dg(iter)=0.5*(1-c)^2*sum(g.^2)+lambda*tau+c*g'*x;
    
    
    tt(iter)=toc;
    
    if dg(iter) <= param.epsStop,
        if param.debug,
            disp('Terminating successfully with small duality gap');
        end
        break;
    end
    
    %% Debug mode
    
    if param.debug && iter>1,
        maxvals=[maxvals maxval];
    end
    
end

if iter>= max_nb_iter,
    disp('Max number of iterations reached in solve_fw');
end


%% Hist outputs

iter=min(iter,max_nb_iter);
burn_in=min(1,iter);

hist.obj = obj(burn_in:iter);
hist.pen =  pen(burn_in:iter);
hist.loss =  loss(burn_in:iter);
hist.dg =  dg(burn_in:iter);
hist.tt =  tt(burn_in:iter);
if strcmp(param.method,'asqp')
    hist.nb_pivot=nb_pivot(burn_in:iter);
    hist.active_var= active_var(burn_in:iter);
end

%% Debug figures
if param.debug
    
    figure(10);clf;
    subplot(2,3,1);
    plot(burn_in:iter,hist.obj,'b.');
    title('objective');
    subplot(2,3,2);
    plot(burn_in:iter,hist.loss,'b.');
    title('loss');
    subplot(2,3,3);
    plot(burn_in:iter,hist.pen,'b.');
    title('\lambda.NormUpBd');
    subplot(2,3,4);
    semilogy(burn_in:iter,hist.dg,'b-');
    title('duality gap');
    subplot(2,3,5)
    plot(maxvals);
    title('maxvals');
    
    
    figure(11)
    imagesc(as.atoms(:,1:atom_count));
    xlabel('atom index');
    title('Atoms selected');
    if strcmp(param.method,'asqp')
        total_piv=cumsum(hist.nb_pivot);
        total_piv=total_piv(burn_in:iter);
        figure(15);clf;
        subplot(2,2,1);
        bar(hist.nb_pivot);
        xlim([0 length(total_piv)])
        pbaspect([1,1,1])
        ylabel('#pivots');
        xlabel('iterations');
        title('#pivots per Active-Set call');
        subplot(2,2,2);
        bar(total_piv);
        xlim([0 length(total_piv)])
        pbaspect([1,1,1])
        xlabel('iterations');
        ylabel('#total pivots');
        title('total #pivots');
        subplot(2,2,3);
        bar(hist.active_var,'FaceColor',[.6 0 0]);
        pbaspect([2,1,1])
        xlabel('iterations');
        ylabel('#active variables');
        %legend('active', 'non-active');
        title('#active variables during iterations');
    end
    keyboard;
    
end




