require(rvest)
require(XML)
require(dplyr)
require(magrittr)

quartzFonts(HiraKaku=quartzFont(rep("HiraKakuPro-W3",4)))
par(family="HiraKaku")

# 番組表 ----
  
table <- xml2::read_html("https://www.gtv.co.jp/program/schedule.html")

# 実行当日の番組表の操作
  
# 現在日の取得
current <- table %>% html_nodes(xpath = "//*[@id=\"main\"]/div[2]/div[1]/div[1]/ul/li[1]/div/span/span[1]") %>% html_text() %>% 
  paste0(format(jrvFinance::edate(from = Sys.Date(), 0), "%Y"), "/", .) %>% 
  stringr::str_replace_all(., pattern = "/", replacement = "-")

# 番組名の取得
program_name <- table %>% html_nodes(xpath = "//*[@id=\"today\"]/dl[*]/dd/p[1]") %>% html_text()

# 放送時間の取得
program_time <- table %>% html_nodes(xpath = "//*[@id=\"today\"]/dl[*]/dt") %>% html_text() %>% 
  paste0(., ":00")

# 番組名と放送時間の結合
program <- cbind(program_name,program_time) %>% data.frame(.,stringsAsFactors = FALSE)
program[,1] <- sapply(program[,1], FUN = function(x) Nippon::zen2han(x))

# 日付列の追加
program %<>% dplyr::mutate(date = current)

# 再放送列の追加
program %<>% mutate("re-air" = stringr::str_detect(program$program_name, pattern = "再"))

# 番組名の[再]/[/[を削除
program$program_name <- stringr::str_replace(program$program_name, pattern = "\\[再]", replacement = "")
program$program_name <- stringr::str_replace(program$program_name, pattern = "\\[最終回]", replacement = "")
program$program_name <- stringr::str_replace(program$program_name, pattern = "\\[", replacement = "")
program$program_name <- stringr::str_replace(program$program_name, pattern = "\\]", replacement = "")

# 番組名の全角スペースを半角に変換
program$program_name <- stringr::str_replace_all(program$program_name, pattern = "　", replacement = " ")

# 番組表とカテゴリー一覧のタイトル名が異なる場合の修正
program$program_name <- stringr::str_replace_all(program$program_name
                                                 ,pattern = "レッツゴー カースポット"
                                                 ,replacement = "レッツゴーカースポット"
                                                 )
program$program_name <- stringr::str_replace_all(program$program_name
                                                 ,pattern = "Car-X’s with NAPAC"
                                                 ,replacement = "Car X's with NAPAC"
                                                 )
program$program_name <- stringr::str_replace_all(program$program_name
                                                 ,pattern = "ニュースジャスト6"
                                                 ,replacement = "ニュースJUST6"
                                                 )
program$program_name <- stringr::str_replace_all(program$program_name
                                                 ,pattern = "ニュースジャスト\\d*"
                                                 ,replacement = "ニュースJUST"
                                                 )

over24hours <- function(x){
  as.Date(x) + lubridate::hms(sub(".* ", "", x))
}

# 放送日時列を追加
program$datetime <- paste(program$date, program$program_time) %>% 
  over24hours %>% 
  as.character

# 番組放送時間列を追加
program$duration <- diff(as.POSIXlt(program$datetime)) %>% as.character() %>% append(., NA)

# 関数定義 ----

getCategoryInfo <- function(CATEGORY){
  
  # 番組数の取得
  length <- CATEGORY %>% html_nodes(xpath = "//*[@id=\"main\"]/div[3]/ul/li") %>% length
  
  prog <- c()
  orig <- c()
  
  for(i in 1:length){
    tmp_prog <- CATEGORY %>% html_nodes(xpath = paste0("//*[@id=\"main\"]/div[3]/ul/li["
                                                       ,i
                                                       ,"]/*/div/div[1]/div[2]/dl/dt"
    )
    ) %>%
      html_text()  %>% Nippon::zen2han(.)
    
    prog <- append(prog, tmp_prog)
    
    tmp_orig <- CATEGORY %>% html_nodes(xpath = paste0("//*[@id=\"main\"]/div[3]/ul/li["
                                                       ,i
                                                       ,"]/*/div/div[1]/p"
    )
    ) %>%
      html_text() 
    
    orig <- append(orig, ifelse(identical(tmp_orig, character(0)), "NO", tmp_orig))
  }
  
  return(cbind(prog, orig) %>% data.frame(., stringsAsFactors = FALSE))
}

# ニュース・情報
info <- xml2::read_html("https://www.gtv.co.jp/program/info/") %>% 
  getCategoryInfo() %>% 
  dplyr::mutate("category" = "ニュース・情報")

# 音楽
music <- xml2::read_html("https://www.gtv.co.jp/program/music/") %>% 
  getCategoryInfo() %>% 
  dplyr::mutate("category" = "音楽")

# バラエティ
variety <- xml2::read_html("https://www.gtv.co.jp/program/variety/") %>% 
  getCategoryInfo() %>% 
  dplyr::mutate("category" = "バラエティ")

# アニメ・キッズ
animation <- xml2::read_html("https://www.gtv.co.jp/program/animation/") %>% 
  getCategoryInfo() %>% 
  dplyr::mutate("category" = "アニメ・キッズ")

# スポーツ
sports <- xml2::read_html("https://www.gtv.co.jp/program/sports/") %>% 
  getCategoryInfo() %>% 
  dplyr::mutate("category" = "スポーツ")

# ドラマ
drama <- xml2::read_html("https://www.gtv.co.jp/program/drama/") %>% 
  getCategoryInfo() %>% 
  dplyr::mutate("category" = "ドラマ")

# 教育・旅
education <- xml2::read_html("https://www.gtv.co.jp/program/education/") %>% 
  getCategoryInfo() %>% 
  dplyr::mutate("category" = "教育・旅")

# 番組カテゴリ全結合
all <- rbind(info, music, variety, animation, sports, drama, education)
names(all) <- c("program_name", "orig", "category")

# 番組名の全角スペースを半角に変換
all$program_name <- stringr::str_replace_all(all$program_name, pattern = "　", replacement = " ")

# 番組表と番組カテゴリの結合
program <- dplyr::left_join(program, all, by = "program_name")

# ファイルへ書き出し
FILENAME <- paste0("./Data/", current, ".csv")

write.table(
  program #出力データ
  ,FILENAME #出力先
  ,quote = FALSE #文字列を「"」で囲む有無
  ,col.names = TRUE #変数名(列名)の有無
  ,row.names = FALSE #行番号の有無
  ,sep = "," #区切り文字の指定
)