class SolutionsController < ApplicationController
  before_filter :require_user, :except=> [:submited, :solved, :best, :last]

  layout 'contests'

  def last
    @solutions = Solution.
      find(:all, :limit => 30,
           :include => [:user, :problem],
           :order => 'solutions.uploaded_at desc')
  end

  def show
    @solution = Solution.find(params[:id])
    validate_showable?
  end

  def best
    @problem = Problem.find(params[:problem_id])
    @solution = @problem.best_solution
    unless @solution
      flash[:notice] = 'Энэ бодлогыг одоогоор нэг ч хүн бодоогүй байна'
      redirect_to @problem
    else
      render :partial => 'best'
    end
  end

  def submited
    @problem = Problem.find(params[:problem_id])
    @solutions = @problem.solutions(:include => [:language, :user],
                                    :order => 'uploaded_at DESC')
    if @solutions.empty?
      render :text => 'Энэ бодлогыг одоогоор нэг ч хүн бодоогүй байна'
    else
      render :partial => 'list'
    end
  end

  def solved
    @problem = Problem.find(params[:problem_id])
    @solutions = @problem.solutions.correct(:include => [:language, :user],
                                            :order => 'uploaded_at DESC')
    if @solutions.empty?
      render :text => 'Энэ бодлогыг одоогоор нэг ч хүн зөв бодоогүй байна'
    else
      render :partial => 'list'
    end
  end

  def view
    @solution = Solution.find(params[:id])
    if @solution.owned_by? current_user
      send_file(@solution.source.path, 
                :filename => @solution.source_file_name, 
                :disposition => 'attachment')
      return
    end
    return unless validate_showable?
    solutions = current_user.solved(@solution.problem)
    if solutions.empty?
      flash[:notice] = "Бодлогыг өөрөө бодож чадсаны дараа л бусдын бодолтыг үзэх боломжтой"
      redirect_to @solution.problem
    else
      solutions.each { |solved| solved.lock! }
      send_file(@solution.source.path, 
                :filename => @solution.source_file_name, 
                :disposition => 'attachment')
    end
  end

  def new
    @problem = Problem.find(params[:problem])
    @solution = current_user.last_submission_of(@problem)
    if @solution.nil? || (@solution.contest && @solution.contest.finished?)
      @solution = Solution.new
      @solution.problem_id = @problem.id
      return unless validate_solvable?
    else
      @results = @solution.results
      render :action => 'show'
    end
  end

  def create
    params[:solution].merge!(:uploaded_at => Time.now)
    @solution = current_user.solutions.build(params[:solution])
    @solution.apply_contest
    return unless validate_solvable?
    @last_one = current_user.last_submission_of(@solution.problem)
    if @last_one
      if !@last_one.locked?
        if @last_one.owned_by?(current_user) && !@last_one.freezed?
          @last_one.cleanup!
          @last_one.update_attributes(params[:solution])
        end
      else
        flash[:notice] = "Та хэн нэгний бодолтыг үзчихсэн учраас энэ бодлогыг дахин бодож болохгүй"
        redirect_to @last_one
      end
    else
      if @solution.save
        flash[:notice] = 'Бодолтыг хадгалж авлаа.'
        redirect_to  @solution
      else
        render :action => 'new'
      end
    end
  end

  def edit
    @solution = Solution.find(params[:id])
    return unless validate_solvable?
    return unless validate_touchable?
  end

  def update    
    @solution = Solution.find(params[:id])
    return unless validate_solvable?
    return unless validate_touchable?
    @solution.cleanup!
    params[:solution].merge!(:uploaded_at => Time.now)
    if @solution.update_attributes(params[:solution])
      flash[:notice] = 'Бодолт шинэчлэгдлээ.'
      redirect_to @solution
    else
      render :action => 'edit'
    end
  end

  def destroy
    @solution = Solution.find(params[:id])
    return unless validate_touchable?
    @solution.destroy
    redirect_to @solution.problem
  end

  def check
    @solution = Solution.find(params[:id])
    if !judge?
      if @solution.checked || !@solution.invalidated
        render :text => 'Шалгачихсан'
        return
      end
      if !@solution.owned_by?(current_user)
        render :text => 'Бусдын бодлогыг шалгахгүй!'
        return
      end
    end
    if @solution.problem.tests.size == 0
      render :text => 'Шалгах тэст байхгүй байна'
      return
    end
    flash[:error] = @solution.junk unless @solution.check!
    render :partial => 'results/list'
  end

  private

  def validate_solvable?
    return true unless @solution.contest
    if @solution.problem.owned_by?(current_user) &&
        !@solution.contest.finished?
      flash[:notice] = 'Уучлаарай, өөрийнхөө дэвшүүлсэн бодлогыг тэмцээн дууссаны дараа л бодож болно!.'
      redirect_to @solution.contest
      return false
    elsif !@solution.contest.started?
      flash[:notice] = 'Ирээдүйд болох тэмцээний бодлогыг бодож болохгүй!.'
      redirect_to @solution.contest
      return false
    elsif @solution.contest.finished?
      return true
    elsif @solution.contest.open? ||
        current_user.level > @solution.contest.level
      flash[:notice] = 'Таны түвшин энэ тэмцээнийхээс дээгүүр байна.'
      redirect_to @solution.contest
      return false
    else
      return true
    end
  end

  def validate_showable?
    if !@solution.contest || @solution.contest.finished? || @solution.owned_by?(current_user)
      return true
    else
      flash[:notice] = 'Тэмцээн дуусаагүй байхад бусдын бодолтыг харахгүй!'
      redirect_to @solution.contest
      return false
    end
  end

  def validate_touchable?
    return true if judge?
    if !@solution.owned_by?(current_user)
      flash[:notice] ='Бусдын бодолтыг өөрчилж болохгүй!'
      redirect_to @solution.problem
      return false
    elsif @solution.locked?
      flash[:notice] ='Энэ бодолтыг өөрчилж болохгүй'
      redirect_to @solution
      return false
    elsif @solution.freezed?
      flash[:notice] ='Тэмцээн дууссан хойно бодолтыг өөрчилж болохгүй!'
      redirect_to @solution.contest
      return false
    end
    true
  end

end
