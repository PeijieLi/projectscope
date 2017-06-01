require 'json'
class ProjectsController < ApplicationController
  before_action :set_project, only: [:show, :edit, :update, :destroy, :add_owner,
                                     :show_metric, :show_report, :get_metric_data]
  before_action :init_existed_configs, only: [:show, :edit, :new]
  before_action :authenticate_user!
  load_and_authorize_resource

  # GET /projects
  # GET /projects.json
  def index
    if current_user.is_student?
      if current_user.project.nil?
        redirect_to init_user_path current_user
      else
        redirect_to project_path current_user.project
      end
    end
    @metric_names = current_user.preferred_metrics
    @current_page = params.has_key?(:page) ? (params[:page].to_i - 1) : 0
    preferred_projects = current_user.preferred_projects.empty? ? Project.all : current_user.preferred_projects
    if params[:type].nil? or params[:type] == "project_name"
      @projects = order_by_project_name preferred_projects
    else
      @projects = order_by_metric_name preferred_projects
    end
    update_session

    metric_min_date = MetricSample.min_date || Date.today
    @num_days_from_today = (Date.today - metric_min_date).to_i
  end

  # GET /projects/1
  # GET /projects/1.json
  def show
    @owners = @project.owners
    metric_min_date = MetricSample.min_date || Date.today
    @num_days_from_today = (Date.today - metric_min_date).to_i
  end

  # GET /projects/new
  def new
    @project = Project.new
    @credentials = ProjectMetrics.metric_names\
                       .flat_map { |m| ProjectMetrics.class_for(m).credentials }\
                       .uniq\
                       .group_by { |name| name.to_s.split('_')[0].to_sym }
  end

  # GET /projects/1/edit
  def edit
    @configs = {}
    all_configs = @project.configs.select(:metric_name, :metrics_params, :token).map(&:attributes)
    all_configs.each do |config|
      @configs[config["metric_name"]] ||= []
      @configs[config["metric_name"]] << {config["metrics_params"] => config["token"]}
    end
  end

  # POST /projects
  # POST /projects.json
  def create
    update_params = project_params
    config_params = update_params.delete 'configs'
    @project = Project.new(update_params)
    ProjectMetrics.metric_names.each do |m|
      ProjectMetrics.class_for(m).credentials.each do |param|
        if config_params.has_key? param.to_s
          @project.configs << Config.new(metric_name: m, metrics_params: param, token: config_params[param])
        end
      end
    end
    respond_to do |format|
      if @project.save
        current_user.preferred_projects << @project
        current_user.owned_projects << @project
        format.html { redirect_to projects_path, notice: 'Project was successfully created.' }
        format.json { render :show, status: :created, location: @project }
      else
        format.html { render :new }
        format.json { render json: @project.errors, status: :unprocessable_entity }
      end
    end
  end

  def get_metric_data
    #from @project to get metric
    days_from_now = params[:days_from_now] ? params[:days_from_now].to_i : 0
    date = DateTime.parse((Date.today - days_from_now.days).to_s)
    # metric = MetricSample.find_by project_id:params[:id], metric_name:params[:metric]
    metric = @project.metric_on_date params[:metric], date
    if metric.length > 0
      render json: metric[0]
    else
      render :json => {:error => "not found"}.to_json, :status => 404
    end
  end

  # PATCH/PUT /projects/1
  # PATCH/PUT /projects/1.json
  def update
    update_params = project_params
    config_params = update_params.delete 'configs'
    notice = ''
    @project.configs.each do |config|
      if config_params.has_key? config.metric_name and config_params[config.metric_name].has_key? config.metrics_params
        config.token = config_params[config.metric_name][config.metrics_params]
        notice += "Failed to update config #{config.metric_name}: #{config.metrics_params}\n" unless config.save
      end
    end
    @project.attributes = update_params
    respond_to do |format|
      if @project.save
        format.html { redirect_to projects_path, notice: 'Project was successfully updated.' + notice }
        format.json { render :show, status: :ok, location: @project }
      else
        format.html { render :edit }
        format.json { render json: @project.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /projects/1
  # DELETE /projects/1.json
  def destroy
    @project.destroy
    respond_to do |format|
      format.html { redirect_to projects_url, notice: 'Project was successfully destroyed.' }
      format.json { head :no_content }
    end
  end

  def show_metric
    total_hash = current_user.preferred_metrics.inject(Hash.new) do |sum, elem|
      sum.update(elem)
    end
    @sub_metrics = total_hash[params[:metric]]
    @practice_name = params[:metric]
    @days_from_now = params[:days_from_now]? params[:days_from_now].to_i : 0
    @parent_metric = @project.metric_on_date params[:metric], DateTime.parse((Date.today - @days_from_now.days).to_s)
    @parent_metric = @parent_metric.length > 0 ? @parent_metric[0] : false

    metric_min_date = MetricSample.min_date || Date.today
    @num_days_from_today = (Date.today - metric_min_date).to_i
    render template: 'projects/metric_detail'
  end

  def show_report
    report = ProjectMetrics.hierarchies(:report).select { |m| m[:title].eql? params[:metric].to_sym }.first
    @sub_metrics = report[:contents]
    @practice_name = report[:title].to_s
    @days_from_now = 0
    @parent_metric = @project.latest_metric_sample params[:metric]
    metric_min_date = MetricSample.min_date || Date.today
    @num_days_from_today = (Date.today - metric_min_date).to_i
    render template: 'projects/metric_detail'
  end

  def add_owner
    new_username = params[:username]
    new_owner = User.find_by_provider_username new_username
    if current_user.is_owner_of? @project and !new_owner.nil?
      begin
        @project.owners << new_owner
        flash[:notice] = "#{new_username} has become an owner of this project!"
      rescue
        flash[:alert] = "Failed to add #{new_username} as owner."
      end
    end
    redirect_to project_path(@project)
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_project
    @project = Project.includes(:configs).find(params[:id])
  end

  def init_existed_configs
    @existed_configs = {}
    ProjectMetrics.metric_names.each do |name|
      @existed_configs[name] = []
    end
  end

  # Never trust parameters from the scary internet, only allow the white list through.
  def project_params
    params[:project]
  end

  def order_by_project_name(preferred_projects)
    session[:order] = "ASC" if session[:pre_click] != "project_name"
    preferred_projects.order_by_name(session[:order])
  end

  def order_by_metric_name(preferred_projects)
    click_type = params[:type]
    session[:order] = "ASC" if session[:pre_click] != click_type
    preferred_projects.order_by_metric_score(click_type, session[:order])
  end

  def update_session
    session[:order] = session[:order] == "ASC" ? "DESC" : "ASC"
    session[:pre_click] = params[:type]
  end


  # get path: projects/:id/
  # param metric_name string:"github"
  # return all data from matrics_smaple of github relate to this project
  def metrics_data(id, metric_name)
    MetricSample.latest_metric(id, metric_name)
  end

end
