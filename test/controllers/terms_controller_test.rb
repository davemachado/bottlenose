require 'test_helper'

class TermsControllerTest < ActionController::TestCase
  setup do
    @term = create(:term)
    @ken  = create(:admin_user)

    @bad  = create(:term)
  end

  test "should get index" do
    get :index, {}, {user_id: @ken.id}
    assert_response :success
    assert_not_nil assigns(:terms)
  end

  test "should get new" do
    get :new, {}, {user_id: @ken.id}
    assert_response :success
  end

  test "should create term" do
    assert_difference('Term.count') do
      post :create, {term: { name: @term.name }}, {user_id: @ken.id}
    end

    assert_redirected_to term_path(assigns(:term))
  end

  test "should show term" do
    get :show, {id: @term}, {user_id: @ken.id}
    assert_response :success
  end

  test "should get edit" do
    get :edit, {id: @term}, {user_id: @ken.id}
    assert_response :success
  end

  test "should update term" do
    put :update, {id: @term, term: { name: @term.name }}, {user_id: @ken.id}
    assert_redirected_to term_path(assigns(:term))
  end

  test "should destroy term" do
    assert_difference('Term.count', -1) do
      delete :destroy, {id: @bad}, {user_id: @ken.id}
    end

    assert_redirected_to terms_path
  end
end
