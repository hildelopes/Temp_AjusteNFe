*&---------------------------------------------------------------------*
*& Report  ZREPORT_AJUSTE_NFE
*& Ajuste de NF-e via BDC - Transação J1B2N (múltiplos documentos)
*&---------------------------------------------------------------------*
REPORT zreport_ajuste_nfe.

TABLES: j_1bnfdoc.

TYPES: BEGIN OF ty_nfdoc,
         docnum TYPE j_1bnfdoc-docnum,
         series TYPE j_1bnfdoc-series,
         docdat TYPE j_1bnfdoc-docdat,
         pstdat TYPE j_1bnfdoc-pstdat,
         nfenum TYPE j_1bnfdoc-nfenum,
       END OF ty_nfdoc.

TYPES: BEGIN OF ty_nflin,
         docnum     TYPE j_1bnflin-docnum,
         itmnum     TYPE j_1bnflin-itmnum,
         itmtyp     TYPE j_1bnflin-itmtyp,
         charg      TYPE j_1bnflin-charg,
         cfop       TYPE j_1bnflin-cfop,
         taxlw1     TYPE j_1bnflin-taxlw1,
         matorg     TYPE j_1bnflin-matorg,
         taxlw2     TYPE j_1bnflin-taxlw2,
         taxlw4     TYPE j_1bnflin-taxlw4,
         nbm        TYPE j_1bnflin-nbm,
         taxlw5     TYPE j_1bnflin-taxlw5,
         classtrib  TYPE j_1bnflin-classtrib,
         cod_cta    TYPE j_1bnflin-cod_cta,
         num_item   TYPE j_1bnflin-num_item,
         menge_trib TYPE j_1bnflin-menge_trib,
         meins_trib TYPE j_1bnflin-meins_trib,
       END OF ty_nflin.

DATA: gt_nfdoc   TYPE TABLE OF ty_nfdoc,
      gs_nfdoc   TYPE ty_nfdoc,
      gt_nflin   TYPE TABLE OF ty_nflin,
      gs_nflin   TYPE ty_nflin,
      gv_mode    TYPE c VALUE 'N',
      gv_date_f  TYPE char10,
      gv_menge_f TYPE char18.

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME.
  SELECT-OPTIONS: s_docnum FOR j_1bnfdoc-docnum OBLIGATORY.
  PARAMETERS:     p_mode   TYPE c DEFAULT 'N'.
SELECTION-SCREEN END OF BLOCK b1.

START-OF-SELECTION.

  gv_mode = p_mode.

  " Buscar todos os documentos da seleção
  SELECT docnum series docdat pstdat nfenum
    INTO CORRESPONDING FIELDS OF TABLE gt_nfdoc
    FROM j_1bnfdoc
   WHERE docnum IN s_docnum.

  IF sy-subrc <> 0.
    MESSAGE 'Nenhum documento encontrado para a seleção informada.' TYPE 'E'.
  ENDIF.

  " Processar cada documento
  LOOP AT gt_nfdoc INTO gs_nfdoc.
    WRITE: / |===> Processando documento: { gs_nfdoc-docnum }|.
    PERFORM f_bdc_ajuste.
    SKIP.
  ENDLOOP.

*----------------------------------------------------------------------*
FORM f_bdc_ajuste.

  DATA: lt_bdcdata TYPE TABLE OF bdcdata,
        lt_bdcmsg  TYPE TABLE OF bdcmsgcoll.

  " Buscar itens do documento atual
  CLEAR gt_nflin.
  SELECT docnum itmnum itmtyp charg cfop taxlw1 matorg taxlw2
         taxlw4 nbm taxlw5 classtrib cod_cta num_item menge_trib meins_trib
    INTO CORRESPONDING FIELDS OF TABLE gt_nflin
    FROM j_1bnflin
   WHERE docnum = gs_nfdoc-docnum.

  IF sy-subrc <> 0.
    WRITE: / |  AVISO: Nenhum item encontrado para o documento { gs_nfdoc-docnum }. Pulando.|.
    RETURN.
  ENDIF.

  WRITE gs_nfdoc-docdat TO gv_date_f DD/MM/YYYY.
  REPLACE ALL OCCURRENCES OF '/' IN gv_date_f WITH '.'.

  " --- Tela inicial: informar DOCNUM ---
  PERFORM f_bdc_dynpro USING 'SAPMJ1B1' '1100' CHANGING lt_bdcdata.
  PERFORM f_bdc_field  USING 'BDC_CURSOR'       'J_1BDYDOC-DOCNUM'  CHANGING lt_bdcdata.
  PERFORM f_bdc_field  USING 'BDC_OKCODE'       '/00'               CHANGING lt_bdcdata.
  PERFORM f_bdc_field  USING 'J_1BDYDOC-DOCNUM' gs_nfdoc-docnum     CHANGING lt_bdcdata.

  " --- Tela 2000: cabeçalho ---
  PERFORM f_bdc_dynpro USING 'SAPLJ1BB2' '2000' CHANGING lt_bdcdata.
  PERFORM f_bdc_field  USING 'BDC_OKCODE'       '=LIDE'             CHANGING lt_bdcdata.
  PERFORM f_bdc_field  USING 'J_1BDYDOC-SERIES' gs_nfdoc-series     CHANGING lt_bdcdata.
  PERFORM f_bdc_field  USING 'J_1BDYDOC-DOCDAT' gv_date_f           CHANGING lt_bdcdata.
  PERFORM f_bdc_field  USING 'J_1BDYDOC-PSTDAT' gv_date_f           CHANGING lt_bdcdata.
  PERFORM f_bdc_field  USING 'BDC_SUBSCR'
    'SAPLJ1BB2                               5400MAIN_PARTNER'       CHANGING lt_bdcdata.
  PERFORM f_bdc_field  USING 'BDC_SUBSCR'
    'SAPLJ1BB2                               2100HEADER_TAB'         CHANGING lt_bdcdata.
  PERFORM f_bdc_field  USING 'BDC_CURSOR'       'J_1BDYLIN-TMISS(01)' CHANGING lt_bdcdata.
  PERFORM f_bdc_field  USING 'BDC_SUBSCR'
    'SAPLJ1BB2                               2002NF_NUMBER'          CHANGING lt_bdcdata.
  PERFORM f_bdc_field  USING 'J_1BDYDOC-NFENUM' gs_nfdoc-nfenum     CHANGING lt_bdcdata.

  " --- Tela 3000: itens ---
  LOOP AT gt_nflin INTO gs_nflin.

    WRITE gs_nflin-menge_trib TO gv_menge_f.
    CONDENSE gv_menge_f.

    PERFORM f_bdc_dynpro USING 'SAPLJ1BB2' '3000' CHANGING lt_bdcdata.
    PERFORM f_bdc_field  USING 'BDC_OKCODE'           '=SAVE'               CHANGING lt_bdcdata.
    PERFORM f_bdc_field  USING 'J_1BDYDOC-SERIES'     gs_nfdoc-series       CHANGING lt_bdcdata.
    PERFORM f_bdc_field  USING 'BDC_SUBSCR'
      'SAPLJ1BB2                               5400MAIN_PARTNER'             CHANGING lt_bdcdata.
    PERFORM f_bdc_field  USING 'BDC_SUBSCR'
      'SAPLJ1BB2                               3100ITEM_TABS'                CHANGING lt_bdcdata.
    PERFORM f_bdc_field  USING 'BDC_CURSOR'           'J_1BDYLIN-CLASSTRIB'  CHANGING lt_bdcdata.
    PERFORM f_bdc_field  USING 'J_1BDYLIN-ITMTYP'     gs_nflin-itmtyp       CHANGING lt_bdcdata.
    PERFORM f_bdc_field  USING 'J_1BDYLIN-CHARG'      gs_nflin-charg        CHANGING lt_bdcdata.
    PERFORM f_bdc_field  USING 'J_1BDYLIN-CFOP'       gs_nflin-cfop         CHANGING lt_bdcdata.
    PERFORM f_bdc_field  USING 'J_1BDYLIN-TAXLW1'     gs_nflin-taxlw1       CHANGING lt_bdcdata.
    PERFORM f_bdc_field  USING 'J_1BDYLIN-MATORG'     gs_nflin-matorg       CHANGING lt_bdcdata.
    PERFORM f_bdc_field  USING 'J_1BDYLIN-TAXLW2'     gs_nflin-taxlw2       CHANGING lt_bdcdata.
    PERFORM f_bdc_field  USING 'J_1BDYLIN-TAXLW4'     gs_nflin-taxlw4       CHANGING lt_bdcdata.
    PERFORM f_bdc_field  USING 'J_1BDYLIN-NBM'        gs_nflin-nbm          CHANGING lt_bdcdata.
    PERFORM f_bdc_field  USING 'J_1BDYLIN-TAXLW5'     gs_nflin-taxlw5       CHANGING lt_bdcdata.
    PERFORM f_bdc_field  USING 'J_1BDYLIN-CLASSTRIB'  gs_nflin-classtrib    CHANGING lt_bdcdata.
    PERFORM f_bdc_field  USING 'BDC_SUBSCR'
      'SAPLJ1BB2                               3110SUB1'                     CHANGING lt_bdcdata.
    PERFORM f_bdc_field  USING 'J_1BDYLIN-COD_CTA'    gs_nflin-cod_cta      CHANGING lt_bdcdata.
    PERFORM f_bdc_field  USING 'J_1BDYLIN-NUM_ITEM'   gs_nflin-num_item     CHANGING lt_bdcdata.
    PERFORM f_bdc_field  USING 'J_1BDYLIN-MENGE_TRIB' gv_menge_f            CHANGING lt_bdcdata.
    PERFORM f_bdc_field  USING 'J_1BDYLIN-MEINS_TRIB' gs_nflin-meins_trib   CHANGING lt_bdcdata.
    PERFORM f_bdc_field  USING 'BDC_SUBSCR'
      'SAPLJ1BB2                               2002NF_NUMBER'                CHANGING lt_bdcdata.
    PERFORM f_bdc_field  USING 'J_1BDYDOC-NFENUM'     gs_nfdoc-nfenum       CHANGING lt_bdcdata.

  ENDLOOP.

  " --- Retorno à tela inicial ---
  PERFORM f_bdc_dynpro USING 'SAPMJ1B1' '1100' CHANGING lt_bdcdata.
  PERFORM f_bdc_field  USING 'BDC_OKCODE' '/EBACK'            CHANGING lt_bdcdata.
  PERFORM f_bdc_field  USING 'BDC_CURSOR' 'J_1BDYDOC-DOCNUM'  CHANGING lt_bdcdata.

  CALL TRANSACTION 'J1B2N'
    USING    lt_bdcdata
    MODE     gv_mode
    UPDATE   'S'
    MESSAGES INTO lt_bdcmsg.

  PERFORM f_check_messages USING lt_bdcmsg.

ENDFORM.

*----------------------------------------------------------------------*
FORM f_bdc_dynpro USING pv_prog TYPE any
                        pv_dyn  TYPE any
                  CHANGING ct_bdc TYPE TABLE.
  DATA ls_bdc TYPE bdcdata.
  ls_bdc-program  = pv_prog.
  ls_bdc-dynpro   = pv_dyn.
  ls_bdc-dynbegin = 'X'.
  APPEND ls_bdc TO ct_bdc.
ENDFORM.

FORM f_bdc_field USING pv_fname TYPE any
                       pv_fval  TYPE any
                 CHANGING ct_bdc TYPE TABLE.
  DATA ls_bdc TYPE bdcdata.
  ls_bdc-fnam = pv_fname.
  ls_bdc-fval = pv_fval.
  APPEND ls_bdc TO ct_bdc.
ENDFORM.

*----------------------------------------------------------------------*
FORM f_check_messages USING pt_msg TYPE TABLE.
  DATA: ls_msg  TYPE bdcmsgcoll,
        lv_txt  TYPE string,
        lv_erro TYPE abap_bool VALUE abap_false.

  LOOP AT pt_msg INTO ls_msg.
    CALL FUNCTION 'MESSAGE_TEXT_BUILD'
      EXPORTING
        msgid               = ls_msg-msgid
        msgnr               = ls_msg-msgnr
        msgv1               = ls_msg-msgv1
        msgv2               = ls_msg-msgv2
        msgv3               = ls_msg-msgv3
        msgv4               = ls_msg-msgv4
      IMPORTING
        message_text_output = lv_txt.
    WRITE: / |  { ls_msg-msgtyp }: { lv_txt }|.
    IF ls_msg-msgtyp CA 'EA'.
      lv_erro = abap_true.
    ENDIF.
  ENDLOOP.

  IF lv_erro = abap_true.
    WRITE: / '  *** ERRO no BDC. ***'.
  ELSE.
    WRITE: / '  >>> BDC executado com sucesso. <<<'.
  ENDIF.
ENDFORM.
