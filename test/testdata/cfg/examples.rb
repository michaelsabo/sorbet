class Examples
  def i_like_ifs()
    if true
      return 1
    else
      return 2
    end
  end

    def i_like_exps()
      if (true)
        1
      else
        2
      end
    end

    def return_in_one_branch1()
      if (true)
        return 1
      else
        2
      end
    end

    def return_in_one_branch2()
      if (true)
        1
      else
        return 2
      end
    end

end